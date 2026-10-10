"""Associate native English OCR lines with the existing comic contours and ink cleanup."""
from copy import deepcopy
import uuid
import cv2
import numpy as np

from balloon_geometry import sampled_shape, source_background
from balloon_lobes import source_rectangle
from balloon_partition import shared_contour
from erase_supplemental_text import glyph_mask, complete_confirmed_glyph_mask
from text_region_geometry import intersection_area, validate_box, rectangular_enclosure


def _ordered(lines: list[dict]) -> list[dict]:
    return sorted(lines, key=lambda line: (line["box"]["y"], line["box"]["x"]))


def _joined_box(lines: list[dict]) -> dict:
    if len(lines) == 1:
        return lines[0]["box"].copy()
    left = min(line["box"]["x"] for line in lines)
    top = min(line["box"]["y"] for line in lines)
    right = max(line["box"]["x"] + line["box"]["width"] for line in lines)
    bottom = max(line["box"]["y"] + line["box"]["height"] for line in lines)
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def _validate_observations(observations: list[dict]) -> None:
    identifiers = set()
    for line in observations:
        validate_box(line["box"])
        if line["id"] in identifiers or not line["originalText"].strip():
            raise ValueError("Duplicate or empty English OCR line")
        identifiers.add(line["id"])


def _shape(line, detected, geometry, width, height):
    box = line["box"]
    matches = []
    for target in detected:
        x1, y1, x2, y2 = target.xyxy
        bounds = {"x": x1 / width, "y": y1 / height, "width": (x2 - x1) / width, "height": (y2 - y1) / height}
        if intersection_area(box, bounds) >= box["width"] * box["height"] * .8:
            matches.append(target)
    if len(matches) == 1:
        target = matches[0]
        bounds = tuple(map(int, target.xyxy))
        return _reading_shape(box, geometry), bounds
    return _reading_shape(box, geometry), None


def _reading_shape(box, geometry):
    """A drawing-filled panel is not a balloon even when its paper is mostly white."""
    font = box["height"] * geometry.height
    enclosure = geometry.enclosure(box, font)
    if enclosure is None:
        return None
    mask, x, y = enclosure
    h, w = mask.shape
    left, top, right, bottom = source_rectangle(box, geometry.width, geometry.height)
    background = source_background(geometry.source[top:bottom, left:right], geometry.glyphs(left, top, right-left, bottom-top))
    if background is None:
        return None
    writable = (cv2.erode(mask, np.ones((5, 5), np.uint8)) > 0) & (geometry.glyphs(x, y, w, h) == 0)
    unknown = ((np.abs(geometry.source[y:y+h, x:x+w].astype(float) - background).max(axis=2) > 45)
               & writable).astype(np.uint8)
    _, _, sizes, _ = cv2.connectedComponentsWithStats(unknown, 8)
    if len(sizes) > 1 and sizes[1:, 4].max() > max(4, font * font * .25):
        return None
    return sampled_shape(mask, x, y, geometry.width, geometry.height, (box["x"] + box["width"] / 2) * geometry.width - x)


def _same_paragraph(group, line, image, mask):
    previous = group["lines"][-1]
    a, b = previous["box"], line["box"]
    overlap = min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"])
    gap = b["y"] - a["y"] - a["height"]
    height = min(a["height"], b["height"])
    if overlap < min(a["width"], b["width"]) * .45 or not -height * .2 <= gap <= height * .8:
        return False
    # A frame or drawing between nearby lines prevents accidental paragraph joins.
    h, w = image.shape[:2]
    left, right = round(max(a["x"], b["x"]) * w), round(min(a["x"] + a["width"], b["x"] + b["width"]) * w)
    top, bottom = round((a["y"] + a["height"]) * h), round(b["y"] * h)
    if bottom <= top:
        return True
    patch = image[top:bottom, left:right]
    if not patch.size:
        return False
    unknown = patch.min(axis=2) < 150
    if mask is not None:
        unknown &= mask[top:bottom, left:right] == 0
    return np.count_nonzero(unknown) < patch.shape[0] * patch.shape[1] * .05


def recognize_blocks(image, detected, observations: list[dict], geometry, prior_blocks: list[dict] | None = None) -> list[dict]:
    _validate_observations(observations)
    height, width = image.shape[:2]
    groups = []
    for line in _ordered(observations):
        shape, bounds = _shape(line, detected, geometry, width, height)
        matching = [group for group in groups if _same_paragraph(group, line, image, geometry.text_mask)
                    and _same_space(group, shape, bounds)]
        if len(matching) == 1:
            matching[0]["lines"].append(line)
            if shape is None:
                matching[0]["shape"] = None
        else:
            groups.append({"shape": shape, "bounds": bounds, "lines": [line]})
    blocks = []
    for group in groups:
        lines = _ordered(group["lines"])
        shape = group["shape"]
        box = _joined_box(lines)
        text = " ".join(line["originalText"].strip() for line in lines)
        prior = [entry for entry in prior_blocks or [] if entry["box"] == box and entry["originalText"] == text]
        # A cleanup refresh must keep the IDs that own manual review edits.
        # Ambiguous or changed OCR never inherits an old region's identity.
        identifier = prior[0]["id"] if len(prior) == 1 else str(uuid.uuid4())
        block = {"id": identifier, "box": box,
                 "originalText": text, "translatedText": "",
                 "confidence": min(line["confidence"] for line in lines), "sourceIsVertical": False,
                 "detectedFontSize": min(line["box"]["height"] for line in lines) * height,
                 "rotationDegrees": 0, "balloonShape": shape}
        if shape is not None:
            block["textKind"] = "caption" if rectangular_enclosure(shape) else "dialogue"
        blocks.append(block)
    return blocks


def _same_space(group, shape, bounds):
    if shape is not None and group["shape"] is not None:
        a, b = shape["bounds"], group["shape"]["bounds"]
        # Native cap-height varies by line. Colour-contour closing therefore
        # shifts a few pixels on the same balloon; Japanese column partitioning
        # keeps its stricter contract. The paragraph test still requires a
        # clear gap and aligned lines before accepting this contour agreement.
        return shared_contour(shape, group["shape"]) or intersection_area(a, b) >= max(a["width"] * a["height"], b["width"] * b["height"]) * .85
    return bounds == group["bounds"] or bounds is None or group["bounds"] is None


def read_regions(regions: list[dict], observations: list[dict]) -> list[dict]:
    _validate_observations(observations)
    if len(regions) > 40:
        raise ValueError("Too many proposed English regions")
    recognized = []
    for region in regions:
        bounds = region.get("userDefinedBounds") or region["box"]
        validate_box(bounds)
        lines = []
        for line in observations:
            box = line["box"]
            overlap = intersection_area(bounds, box)
            if overlap >= box["width"] * box["height"] * .9:
                lines.append(line)
            elif overlap > box["width"] * box["height"] * .15:
                raise ValueError("English selection cuts across a recognized line")
        updated = deepcopy(region)
        updated.pop("recognitionAlternatives", None)
        updated["originalText"] = " ".join(line["originalText"].strip() for line in _ordered(lines))
        recognized.append(updated)
    return recognized


def observed_ink(image, observations: list[dict]):
    _validate_observations(observations)
    height, width = image.shape[:2]
    regions = []
    for line in observations:
        left, top, right, bottom = source_rectangle(line["box"], width, height)
        # Native OCR boxes touch cap-height glyphs. Give the existing bounded
        # stroke selector background samples without granting a filled rectangle.
        padding = max(3, int((bottom - top) * .25))
        left, top = max(0, left - padding), max(0, top - padding)
        right, bottom = min(width, right + padding), min(height, bottom + padding)
        regions.append({"x": left / width, "y": top / height,
                        "width": (right - left) / width, "height": (bottom - top) / height})
    # Native line evidence includes one-pixel periods/dots in small scans.
    # Keep the Japanese/manual selector's stricter default component size.
    mask, boxes = glyph_mask(image, regions, bounded=True, minimum_component_area=1)
    completed = mask.copy()
    for left, top, right, bottom in boxes:
        completed[top:bottom, left:right] |= complete_confirmed_glyph_mask(image[top:bottom, left:right], mask[top:bottom, left:right])
    return completed, boxes
