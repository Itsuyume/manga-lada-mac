"""Locate unrecognized enclosed lettering before OCR; never modify page pixels."""
from dataclasses import dataclass
import cv2
import numpy as np
from dotted_balloon import short_fragments, enclosed_holes


@dataclass
class BalloonCandidate:
    bounds: tuple[int, int, int, int]
    interior: np.ndarray
    ink: np.ndarray


def balloon_candidates(source: np.ndarray, occupied: list[tuple[int, int, int, int]],
                       limit: int = 8, *, connected_lettering: bool = False) -> list[BalloonCandidate]:
    """Use closed/broken borders plus flat interiors as crop proposals, not OCR results.

    Bounded to 1280 pixels and eight crops. Local text detection must still
    confirm every proposal; neither a colour patch nor OCR hallucination is
    sufficient to erase or translate anything.
    """
    if source.ndim != 3 or source.shape[2] != 3 or min(source.shape[:2]) < 2:
        raise ValueError("Expected a nonempty BGR page")
    if limit < 0:
        raise ValueError("Candidate limit cannot be negative")
    height, width = source.shape[:2]
    for x1, y1, x2, y2 in occupied:
        if not 0 <= x1 < x2 <= width or not 0 <= y1 < y2 <= height:
            raise ValueError("Occupied rectangle lies outside the page")
    scale = min(1., 1280 / max(height, width))
    image = cv2.resize(source, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 40, 100)
    ink = (gray < 150).astype(np.uint8) * 255
    fragments = short_fragments(ink, 16)
    contours = []
    for size in (3, 7, 11):
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))
        barrier = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel)
        outlines, hierarchy = cv2.findContours(barrier, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
        if hierarchy is not None:
            contours.extend(c for c, h in zip(outlines, hierarchy[0]) if h[3] >= 0)
        for hole in enclosed_holes(cv2.dilate(ink, kernel), fragments, 16):
            outlines, _ = cv2.findContours(hole, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            contours.extend(outlines)
    covered = np.zeros(image.shape[:2], np.uint8)
    for x1, y1, x2, y2 in occupied:
        cv2.rectangle(covered, (int(x1 * scale), int(y1 * scale)),
                      (int(np.ceil(x2 * scale)), int(np.ceil(y2 * scale))), 255, -1)
    candidates = []
    for contour in sorted(contours, key=cv2.contourArea):
        candidate = candidate_from_contour(image, covered, contour, connected_lettering=connected_lettering)
        if candidate is None or any(same_candidate(candidate, other) for other in candidates):
            continue
        candidates.append(candidate)
    candidates.sort(key=lambda c: np.count_nonzero(c.ink), reverse=True)
    return [rescaled(candidate, scale, width, height) for candidate in candidates[:limit]]


def candidate_from_contour(image: np.ndarray, covered: np.ndarray, contour: np.ndarray,
                           *, connected_lettering: bool = False) -> BalloonCandidate | None:
    area = cv2.contourArea(contour)
    x, y, width, height = cv2.boundingRect(contour)
    maximum_area = .35 if connected_lettering else .16
    if not 180 <= area <= image.shape[0] * image.shape[1] * maximum_area or min(width, height) < 18:
        return None
    if x <= 1 or y <= 1 or x + width >= image.shape[1] - 1 or y + height >= image.shape[0] - 1:
        return None  # A crop/page edge cannot manufacture an enclosed balloon.
    interior = np.zeros((height, width), np.uint8)
    cv2.drawContours(interior, [contour - [x, y]], -1, 255, -1)
    interior = cv2.erode(interior, np.ones((5, 5), np.uint8))
    patch = image[y:y + height, x:x + width]
    pixels = patch[interior > 0]
    if len(pixels) < 100:
        return None
    bins, counts = np.unique(pixels // 16, axis=0, return_counts=True)
    dominant = bins[counts.argmax()]
    background = np.median(pixels[np.all(pixels // 16 == dominant, axis=1)], axis=0)
    distance = np.abs(patch.astype(np.float32) - background).max(axis=2)
    if np.count_nonzero((distance <= 28) & (interior > 0)) < len(pixels) * .68:
        return None
    foreground = ((distance > 45) & (interior > 0)).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(foreground, 8)
    edge = cv2.dilate((interior == 0).astype(np.uint8), np.ones((3, 3), np.uint8))
    touching = set(np.unique(labels[edge > 0]))
    selected = [i for i in range(1, count) if i not in touching and 4 <= stats[i, 4] <= area * .3]
    if len(selected) < (1 if connected_lettering else 2):
        return None
    if connected_lettering and len(selected) == 1:
        component = stats[selected[0]]
        if component[4] / (component[2] * component[3]) > .7:
            return None  # A filled coloured patch is not a connected glyph.
    glyphs = np.isin(labels, selected).astype(np.uint8) * 255
    amount = np.count_nonzero(glyphs)
    if not max(16, len(pixels) * .008) <= amount <= len(pixels) * .4:
        return None
    uncovered = (glyphs > 0) & (covered[y:y + height, x:x + width] == 0)
    if np.count_nonzero(uncovered) < max(12, amount * .25):
        return None
    return BalloonCandidate((x, y, x + width, y + height), interior, glyphs)


def same_candidate(first: BalloonCandidate, second: BalloonCandidate) -> bool:
    a, b = first.bounds, second.bounds
    intersection = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    return intersection > min((a[2]-a[0]) * (a[3]-a[1]), (b[2]-b[0]) * (b[3]-b[1])) * .7


def rescaled(candidate: BalloonCandidate, scale: float, width: int, height: int) -> BalloonCandidate:
    x1, y1, x2, y2 = (round(value / scale) for value in candidate.bounds)
    x2, y2 = min(width, x2), min(height, y2)
    size = (x2-x1, y2-y1)
    return BalloonCandidate((x1, y1, x2, y2),
        cv2.resize(candidate.interior, size, interpolation=cv2.INTER_NEAREST),
        cv2.resize(candidate.ink, size, interpolation=cv2.INTER_NEAREST))
