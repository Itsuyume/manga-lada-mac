"""Propose isolated sentence-final rings; the caller must confirm them with manga OCR."""
from dataclasses import dataclass
import math

import cv2
import numpy as np
import text_region_geometry as geometry


@dataclass(frozen=True)
class SentenceEndCandidate:
    block_id: str
    original_text: str
    crop: tuple[int, int, int, int]
    box: dict  # Complete, isolated mask region including its measured margin.


def sentence_end_candidates(image: np.ndarray, blocks: list[dict]) -> list[SentenceEndCandidate]:
    """Propose the final reading line of unmodified text in a measured balloon."""
    height, width = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    proposed = []
    for block in blocks:
        geometry.validate_box(block["box"])
        font = block["detectedFontSize"]
        if not math.isfinite(font) or font <= 0:
            raise ValueError("Invalid punctuation font scale")
        if not eligible(block):
            continue
        if any(other["id"] != block["id"] and geometry.intersection_area(block["box"], other["box"]) > 0 for other in blocks):
            continue
        text, band = end_band(block, width, height)
        vertical = block["sourceIsVertical"]
        transverse = text[2] - text[0] if vertical else text[3] - text[1]
        multiline = transverse > font * 1.5
        if multiline:
            band = last_line_band(gray, text, font, vertical)
            if band is None:
                continue
        rings = ring_boxes(gray, band, font)
        if multiline:
            rings = [ring for ring in rings if terminates_line(gray, ring, band, font, vertical)]
        rings = [ring for ring in rings if inside_shape(ring, block["balloonShape"], width, height)]
        if len(rings) != 1:
            continue
        left, top, right, bottom = rings[0]
        box = dict(x=left/width, y=top/height, width=(right-left)/width, height=(bottom-top)/height)
        if any(other["id"] != block["id"] and geometry.intersection_area(box, other["box"]) > 0 for other in blocks):
            continue
        crop = (min(text[0], left), min(text[1], top), max(text[2], right), max(text[3], bottom))
        proposed.append(SentenceEndCandidate(block["id"], block["originalText"], crop, box))
    return [candidate for candidate in proposed
            if sum(geometry.intersection_area(candidate.box, other.box) > 0 for other in proposed) == 1]


def confirms_sentence_end(candidate: SentenceEndCandidate, recognized: str | None) -> bool:
    source = candidate.original_text.strip()
    if not source or source.endswith("。") or not isinstance(recognized, str):
        return False
    return recognized.strip() == source + "。"


def eligible(block: dict) -> bool:
    angle = block.get("rotationDegrees") or 0
    if not math.isfinite(angle):
        raise ValueError("Invalid punctuation rotation")
    if block.get("balloonShape") is None or block.get("textKind") in ("title", "soundEffect"):
        return False
    if block.get("userDefinedBounds") is not None or block.get("userDefinedTextKind") is True or block.get("userDefinedOriginalText") is True:
        return False
    if block.get("sourceIsVertical") not in (True, False) or abs(angle) > 5:
        return False
    source = block["originalText"].strip()
    return bool(source) and not source.endswith("。")


def end_band(block: dict, width: int, height: int) -> tuple[tuple, tuple]:
    box, font = block["box"], block["detectedFontSize"]
    left, top = math.floor(box["x"] * width), math.floor(box["y"] * height)
    right, bottom = math.ceil((box["x"] + box["width"]) * width), math.ceil((box["y"] + box["height"]) * height)
    extent, side = math.ceil(font), math.ceil(font * .2)
    if block["sourceIsVertical"]:
        band = (max(0, left-side), bottom, min(width, right+side), min(height, bottom+extent))
    else:
        band = (right, max(0, top-side), min(width, right+extent), min(height, bottom+side))
    return (left, top, right, bottom), band


def ink_mask(crop: np.ndarray) -> np.ndarray:
    if crop.size == 0:
        return np.zeros_like(crop)
    polarity = cv2.THRESH_BINARY if np.median(crop) < 127 else cv2.THRESH_BINARY_INV
    return cv2.threshold(crop, 0, 255, polarity | cv2.THRESH_OTSU)[1]


def last_line_band(gray: np.ndarray, text: tuple, font: float, vertical: bool) -> tuple | None:
    """Separate columns/rows by measured whitespace; Japanese columns read right to left."""
    left, top, right, bottom = text
    binary = ink_mask(gray[top:bottom, left:right])
    occupied = np.flatnonzero(np.any(binary > 0, axis=0 if vertical else 1))
    if not occupied.size:
        return None
    segments = np.split(occupied, np.flatnonzero(np.diff(occupied) > max(2, font * .35)) + 1)
    terminal = segments[0] if vertical else segments[-1]
    start, end = int(terminal[0]), int(terminal[-1]) + 1
    if end - start > font * 1.5:
        return None
    height, width = gray.shape
    side, extent = math.ceil(font * .2), math.ceil(font)
    if vertical:
        return max(0, left+start-side), top, min(width, left+end+side), min(height, bottom+extent)
    return left, max(0, top+start-side), min(width, right+extent), min(height, top+end+side)


def terminates_line(gray: np.ndarray, ring: tuple, band: tuple, font: float, vertical: bool) -> bool:
    left, top, right, bottom = band
    binary = ink_mask(gray[top:bottom, left:right])
    projection = np.any(binary > 0, axis=1 if vertical else 0)
    start = ring[1] - top if vertical else ring[0] - left
    end = ring[3] - top if vertical else ring[2] - left
    preceding = np.flatnonzero(projection[:start])
    if preceding.size < max(3, font * .35) or np.any(projection[end:]):
        return False
    return start - int(preceding[-1]) <= font * 1.25


def ring_boxes(gray: np.ndarray, band: tuple, font: float) -> list[tuple[int, int, int, int]]:
    left, top, right, bottom = band
    crop = gray[top:bottom, left:right]
    if min(crop.shape, default=0) < 9:
        return []
    binary = ink_mask(crop)
    contours, hierarchy = cv2.findContours(binary, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    if hierarchy is None:
        return []
    result = []
    for index, contour in enumerate(contours):
        child, parent = hierarchy[0, index, 2:4]
        if parent != -1 or child == -1:
            continue
        x, y, w, h = cv2.boundingRect(contour)
        if min(w, h) < max(3, font * .1) or max(w, h) > font * .5 or not .65 <= w/h <= 1.5:
            continue
        area = cv2.contourArea(contour)
        if area <= 0 or not .08 <= cv2.contourArea(contours[child]) / area <= .8:
            continue
        pad = max(4, math.ceil(max(w, h) * .12) + 1)
        if min(x, y, crop.shape[1]-x-w, crop.shape[0]-y-h) < pad:
            continue
        # Padding belongs to this ring only; never recruit a second nearby ink component.
        isolated = np.zeros_like(binary)
        cv2.drawContours(isolated, [contour], -1, 255, -1)
        neighborhood = np.zeros_like(binary)
        neighborhood[y-pad:y+h+pad, x-pad:x+w+pad] = 255
        if np.any((binary > 0) & (isolated == 0) & (neighborhood > 0)):
            continue
        result.append((left+x-pad, top+y-pad, left+x+w+pad, top+y+h+pad))
    return result


def inside_shape(box: tuple, shape: dict, width: int, height: int) -> bool:
    left, top, right, bottom = box
    rows = shape["rows"]
    if len(rows) < 3:
        return False
    ys = np.arange(top, bottom) / height
    source_y = [row["y"] for row in rows]
    if ys[0] < source_y[0] or ys[-1] > source_y[-1]:
        return False
    left_edges = np.interp(ys, source_y, [row["left"] for row in rows]) * width
    right_edges = np.interp(ys, source_y, [row["right"] for row in rows]) * width
    return bool(np.all(left >= left_edges+2) and np.all(right <= right_edges-2))
