"""Separate source columns at paired inward contour notches before manga OCR."""
from copy import deepcopy
from dataclasses import dataclass
from itertools import combinations
from typing import TYPE_CHECKING
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry, sampled_shape
from detection_refinement import rectangle

if TYPE_CHECKING:
    from ballontranslator.utils.textblock import TextBlock


@dataclass
class LobeDetections:
    blocks: list["TextBlock"]
    shapes: dict[tuple[int, int, int, int], dict]
    replaced: set[tuple[int, int, int, int]]


def source_rectangle(box: dict, width: int, height: int) -> tuple[int, int, int, int]:
    return (round(box["x"] * width), round(box["y"] * height),
            round((box["x"] + box["width"]) * width), round((box["y"] + box["height"]) * height))


def split_contour(mask: np.ndarray, lines: np.ndarray, font_size: float) -> list[tuple[np.ndarray, list[int]]]:
    """Only split when two significant inward notches separate whole OCR columns."""
    if len(lines) < 2 or font_size <= 0:
        return []
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return []
    contour = max(contours, key=cv2.contourArea)
    if len(contour) < 4:
        return []
    defects = cv2.convexityDefects(contour, cv2.convexHull(contour, returnPoints=False))
    if defects is None:
        return []
    notches = [(contour[index, 0], depth / 256) for _, _, index, depth in defects[:, 0, :]
               if depth / 256 >= max(4, font_size * .4)]
    notches = sorted(notches, key=lambda item: item[1], reverse=True)[:8]
    for (first, _), (second, _) in combinations(notches, 2):
        length = np.linalg.norm(first - second)
        if length < font_size or length > min(mask.shape) * 1.3:
            continue
        divided = mask.copy()
        cv2.line(divided, tuple(first), tuple(second), 0, 2)
        _, labels, stats, _ = cv2.connectedComponentsWithStats(divided, 8)
        groups = column_groups(labels, lines)
        if len(groups) != 2 or any(stats[label, 4] < font_size ** 2 for label in groups):
            continue
        if sum(stats[label, 4] for label in groups) < np.count_nonzero(mask) * .92:
            continue
        return [((labels == label).astype(np.uint8) * 255, indices) for label, indices in groups.items()]
    return []


def column_groups(labels: np.ndarray, lines: np.ndarray) -> dict[int, list[int]]:
    groups: dict[int, list[int]] = {}
    for index, line in enumerate(lines):
        glyph = np.zeros(labels.shape, np.uint8)
        cv2.fillPoly(glyph, [line.astype(np.int32)], 1)
        values, counts = np.unique(labels[glyph > 0], return_counts=True)
        if len(values) == 0:
            return {}
        label = int(values[counts.argmax()])
        if label == 0 or counts.max() < np.count_nonzero(glyph) * .9:
            return {}  # Never cut through an existing Japanese column.
        groups.setdefault(label, []).append(index)
    return groups


def detect_lobes(image: np.ndarray, mask: np.ndarray, blocks: list["TextBlock"]) -> LobeDetections:
    height, width = image.shape[:2]
    geometry = BalloonGeometry(image, text_mask=mask)
    result = LobeDetections([], {}, set())
    for block in blocks:
        if not block.src_is_vertical or len(block.lines) < 2:
            result.blocks.append(block)
            continue
        enclosure = geometry.enclosure(rectangle(block, width, height), block._detected_font_size)
        if enclosure is None:
            result.blocks.append(block)
            continue
        interior, x, y = enclosure
        lines = np.asarray(block.lines)
        parts = split_contour(interior, lines - [x, y], block._detected_font_size)
        if not parts:
            result.blocks.append(block)
            continue
        result.replaced.add(tuple(map(int, block.xyxy)))
        for pixels, indices in parts:
            separated = deepcopy(block)
            separated.lines = lines[indices].tolist()
            extent = lines[indices].reshape(-1, 2)
            separated.xyxy = [int(extent[:, 0].min()), int(extent[:, 1].min()),
                              int(extent[:, 0].max()), int(extent[:, 1].max())]
            center = (separated.xyxy[0] + separated.xyxy[2]) / 2 - x
            shape = sampled_shape(pixels, x, y, width, height, center)
            if shape is None:
                raise ValueError("A separated balloon has no writable rows")
            # Bounds describe this lobe, not the original compound balloon.
            rows = shape["rows"]
            left, right = min(row["left"] for row in rows), max(row["right"] for row in rows)
            top, bottom = min(row["y"] for row in rows), max(row["y"] for row in rows)
            shape["bounds"] = dict(x=left, y=top, width=right-left, height=bottom-top)
            result.blocks.append(separated)
            result.shapes[tuple(separated.xyxy)] = shape
    return result


def retain_cached_regions(blocks: list[dict], replaced: set[tuple], width: int, height: int) -> list[dict]:
    """New lobes receive new OCR IDs; explicit manual regions retain their identity."""
    return [block for block in blocks if block.get("userDefinedBounds") is not None
            or block.get("userDefinedOriginalText") is True or block.get("userDefinedTextKind") is True
            or source_rectangle(block["box"], width, height) not in replaced]
