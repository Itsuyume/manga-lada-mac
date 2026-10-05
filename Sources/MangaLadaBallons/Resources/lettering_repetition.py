"""Resolve adjacent repetition counts using whole-crop evidence and uncut partial views."""
from typing import Callable
import cv2
import numpy as np
from lettering_ocr import japanese_reading, normalized_reading, repeated_unit
from lettering_strokes import complete_stroke_edges, eligible_strokes, stroke_contrast


def disputed_repetition(readings: list[str]) -> str | None:
    """A disputed source repetition needs the same unit in another whole-crop view."""
    if not readings:
        return None
    source = normalized_reading(readings[0])
    unit = repeated_unit(source)
    if unit is None or not japanese_reading(unit):
        return None
    alternatives = {normalized_reading(text) for text in readings}
    return unit if any(text != source and unit * 2 in text for text in alternatives) else None


def repetition_gap(mask: np.ndarray) -> tuple[bool, int] | None:
    """One balanced ink-free band, with clearance, on an elongated single line."""
    height, width = mask.shape
    vertical = height > width
    extent, breadth = (height, width) if vertical else (width, height)
    if extent < breadth * 2:
        return None
    occupied = np.any(mask > 0, axis=1 if vertical else 0)
    empty = np.flatnonzero(~occupied)
    runs = np.split(empty, np.flatnonzero(np.diff(empty) > 1) + 1)
    clearance = max(3, round(breadth * .06))
    candidates = [run for run in runs if len(run) >= clearance
                  and run[0] > extent * .3 and run[-1] < extent * .7]
    if not candidates:
        return None
    gap = min(candidates, key=lambda run: abs(float(run.mean()) - extent / 2))
    return vertical, int((gap[0] + gap[-1] + 1) // 2)


def corroborated_parts(image: np.ndarray, mask: np.ndarray, split: tuple[bool, int],
                       unit: str, recognize: Callable[[np.ndarray], str]) -> str | None:
    """Each unmodified partial source must agree with its isolated ink reading."""
    normalized = stroke_contrast(image)
    isolated = np.full_like(normalized, 255)
    isolated[mask > 0] = normalized[mask > 0]
    vertical, cut = split
    bounds = [(0, cut), (cut, image.shape[0 if vertical else 1])]
    parts, pitches = [], []
    for start, end in bounds:
        source = image[start:end] if vertical else image[:, start:end]
        ink = isolated[start:end] if vertical else isolated[:, start:end]
        part_mask = mask[start:end] if vertical else mask[:, start:end]
        occupied = np.flatnonzero(np.any(part_mask > 0, axis=1 if vertical else 0))
        if np.count_nonzero(part_mask) < 16:
            return None
        text = normalized_reading(recognize(source.copy()))
        if not text or len(text) % len(unit) or text != unit * (len(text) // len(unit)):
            return None
        if normalized_reading(recognize(ink.copy())) != text:
            return None
        parts.append(text)
        pitches.append((occupied[-1] - occupied[0] + 1) / (len(text) // len(unit)))
    return "".join(parts) if max(pitches) <= min(pitches) * 1.5 else None


def recover_repeated_strokes(image: np.ndarray, readings: list[str], masks: list[np.ndarray],
                             recognize: Callable[[np.ndarray], str]) -> tuple[str, np.ndarray] | None:
    """No dictionary guesses: both source/ink halves must agree, with comparable unit width.

    At most two model masks and four OCR calls per mask. No recursive splitting,
    unit substitution, punctuation deletion or general override of source OCR.
    Only the disputed repetition count can change, by at most one occurrence.
    """
    normalized = stroke_contrast(image)
    eligible = eligible_strokes(normalized, masks)
    dispute = disputed_repetition(readings)
    if dispute is None:
        return None
    unit = dispute
    source_count = len(normalized_reading(readings[0])) // len(unit)
    for mask in eligible[:2]:
        split = repetition_gap(mask)
        if split is None:
            continue
        text = corroborated_parts(image, mask, split, unit, recognize)
        count = len(text) // len(unit) if text else 0
        if text is not None and count >= 3 and abs(count - source_count) <= 1:
            gray = cv2.cvtColor(normalized, cv2.COLOR_BGR2GRAY)
            return text, complete_stroke_edges(gray, mask)
    return None
