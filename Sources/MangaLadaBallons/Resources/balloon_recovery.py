"""Confirm outline-first crop proposals at the existing text-detector boundary."""
from copy import deepcopy
from typing import Callable, TYPE_CHECKING
import cv2
import numpy as np
from balloon_candidates import balloon_candidates, BalloonCandidate
from detection_refinement import rectangle, area
from text_region_geometry import intersection_area

if TYPE_CHECKING:
    from ballontranslator.utils.textblock import TextBlock


def recover_balloons(image: np.ndarray, mask: np.ndarray, blocks: list["TextBlock"],
                     detect: Callable, prior: list[dict] | None = None) -> tuple:
    height, width = image.shape[:2]
    if mask.shape != (height, width):
        raise ValueError("Text mask dimensions do not match the page")
    occupied = [tuple(map(int, b.xyxy)) for b in blocks]
    existing_boxes = [rectangle(b, width, height) for b in blocks]
    for block in prior or []:
        box = block.get("userDefinedBounds") or block["box"]
        existing_boxes.append(box)
        occupied.append((int(box["x"] * width), int(box["y"] * height),
                         round((box["x"] + box["width"]) * width), round((box["y"] + box["height"]) * height)))
    candidates = balloon_candidates(image, occupied)
    result, combined = list(blocks), mask.copy()
    for candidate in candidates:
        x1, y1, x2, y2 = candidate.bounds
        pad = max(12, int(min(x2-x1, y2-y1) * .2))
        crop_width, crop_height = min(width, max(512, x2-x1+pad*2)), min(height, max(512, y2-y1+pad*2))
        left = max(0, min(width-crop_width, (x1+x2-crop_width)//2))
        top = max(0, min(height-crop_height, (y1+y2-crop_height)//2))
        right, bottom = left+crop_width, top+crop_height
        crop_mask, found = detect(image[top:bottom, left:right].copy())
        if crop_mask.shape != (bottom-top, right-left):
            raise ValueError("Crop detector mask dimensions do not match its input")
        for block in found:
            translated = translated_detection(block, left, top)
            box = rectangle(translated, width, height)
            if any(intersection_area(box, other) > min(area(box), area(other)) * .05 for other in existing_boxes):
                continue
            accepted = confirmed_mask(candidate, translated, crop_mask, (left, top))
            if accepted is None:
                continue
            combined[y1:y2, x1:x2] |= accepted
            result.append(translated)
            existing_boxes.append(box)
    return combined, result


def translated_detection(block: "TextBlock", x: int, y: int) -> "TextBlock":
    translated = deepcopy(block)
    translated.xyxy = [int(block.xyxy[0]) + x, int(block.xyxy[1]) + y,
                       int(block.xyxy[2]) + x, int(block.xyxy[3]) + y]
    translated.lines = (np.asarray(block.lines) + [x, y]).tolist()
    return translated


def confirmed_mask(candidate: BalloonCandidate, block: "TextBlock", crop_mask: np.ndarray,
                   origin: tuple[int, int]) -> np.ndarray | None:
    x1, y1, x2, y2 = candidate.bounds
    left, top, right, bottom = map(int, block.xyxy)
    if not x1 <= left < right <= x2 or not y1 <= top < bottom <= y2:
        return None
    observed = crop_mask[y1-origin[1]:y2-origin[1], x1-origin[0]:x2-origin[0]].copy()
    bounds = np.zeros(observed.shape, np.uint8)
    bounds[top-y1:bottom-y1, left-x1:right-x1] = 255
    observed &= bounds
    amount = np.count_nonzero(observed)
    if amount < 12 or np.count_nonzero((observed > 0) & (candidate.interior == 0)) > amount * .04:
        return None
    ink = cv2.dilate(candidate.ink, np.ones((3, 3), np.uint8))
    confirmed = cv2.bitwise_and(observed, ink)
    if np.count_nonzero(confirmed) < amount * .35:
        return None
    return confirmed
