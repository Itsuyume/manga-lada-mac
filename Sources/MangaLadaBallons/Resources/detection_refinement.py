"""Reconcile coarse/detailed detector proposals before OCR, without replacing stable text wholesale."""
from typing import TYPE_CHECKING
import numpy as np
from balloon_geometry import BalloonGeometry
from text_region_geometry import intersection_area, validate_box

if TYPE_CHECKING:
    from ballontranslator.utils.textblock import TextBlock


def rectangle(block: "TextBlock", width: int, height: int) -> dict:
    left, top, right, bottom = map(int, block.xyxy)
    box = dict(x=left / width, y=top / height, width=(right - left) / width, height=(bottom - top) / height)
    validate_box(box)
    return box


def area(box: dict) -> float:
    return box["width"] * box["height"]


def missing_detections(detected: list["TextBlock"], prior: list[dict], width: int, height: int) -> list["TextBlock"]:
    boxes = [b["userDefinedBounds"] if b.get("userDefinedBounds") is not None else b["box"] for b in prior]
    for box in boxes:
        validate_box(box)
    return [b for b in detected if not any(intersection_area(rectangle(b, width, height), box)
            > min(area(rectangle(b, width, height)), area(box)) * .05 for box in boxes)]


def separated_detail(base: dict, details: list[dict], sizes: list[float]) -> bool:
    if len(details) != 2 or min(sizes) <= 0 or max(sizes) / min(sizes) < 1.8:
        return False
    first, second = details
    if intersection_area(first, second) > min(area(first), area(second)) * .05:
        return False
    left, top = min(b["x"] for b in details), min(b["y"] for b in details)
    right = max(b["x"] + b["width"] for b in details)
    bottom = max(b["y"] + b["height"] for b in details)
    union = dict(x=left, y=top, width=right - left, height=bottom - top)
    return intersection_area(base, union) >= area(base) * .8 and area(union) <= area(base) * 1.5


def nearby(box: dict, size: float, base: dict, other_size: float, width: int, height: int) -> bool:
    if min(size, other_size) <= 0 or max(size, other_size) / min(size, other_size) > 1.8:
        return False
    dx = max(0, base["x"] - box["x"] - box["width"], box["x"] - base["x"] - base["width"]) * width
    dy = max(0, base["y"] - box["y"] - box["height"], box["y"] - base["y"] - base["height"]) * height
    return max(dx, dy) <= min(size, other_size) * 2


def refine_detection(image: np.ndarray, mask: np.ndarray, base: list["TextBlock"],
                     detail_mask: np.ndarray, details: list["TextBlock"]) -> tuple:
    height, width = image.shape[:2]
    if mask.shape != (height, width) or detail_mask.shape != mask.shape:
        raise ValueError("Detector mask dimensions do not match the page")
    boxes = [rectangle(b, width, height) for b in base]
    fine = [rectangle(b, width, height) for b in details]
    result, accepted = [], []
    for block, box in zip(base, boxes):
        candidates = [i for i, region in enumerate(fine) if intersection_area(box, region) >= area(region) * .85
                      and area(region) < area(box) * .8]
        if separated_detail(box, [fine[i] for i in candidates], [details[i]._detected_font_size for i in candidates]):
            accepted.extend(candidates)
            result.extend(details[i] for i in candidates)
        else:
            result.append(block)
    geometry = BalloonGeometry(image, text_mask=detail_mask)
    for index, (block, box) in enumerate(zip(details, fine)):
        if index in accepted or area(box) > .01 or min(box["width"] * width, box["height"] * height) < 12:
            continue
        if any(intersection_area(box, other) > min(area(box), area(other)) * .05 for other in boxes):
            continue
        if any(intersection_area(box, fine[i]) > 0 for i in accepted):
            continue
        enclosed = geometry.shape(box, block._detected_font_size) is not None
        neighbor = any(nearby(box, block._detected_font_size, other, old._detected_font_size, width, height)
                       for old, other in zip(base, boxes))
        if not enclosed and not neighbor:
            continue
        accepted.append(index)
        result.append(block)
    combined = mask.copy()
    for index in accepted:
        left, top, right, bottom = map(int, details[index].xyxy)
        combined[top:bottom, left:right] |= detail_mask[top:bottom, left:right]
    return combined, result
