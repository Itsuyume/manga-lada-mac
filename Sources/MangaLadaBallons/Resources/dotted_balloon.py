"""Bounded gap closure for broken ink borders; no OCR, colour fill or text layout."""
import cv2
import numpy as np


def dotted_contours(source: np.ndarray, text_mask: np.ndarray | None,
                    rectangle: tuple[float, float, float, float], font_size: float) -> list[np.ndarray]:
    """Approximate only holes enclosed by nearby short border fragments.

    Dilating observed dashes by r closes gaps of at most 2r. Recover the
    enclosed interior, then undo most of that inset, retaining a safety margin.
    Neither a crop edge nor an unobserved long arc can close the enclosure.
    The caller still owns text containment, colour and page-area validation.
    """
    if not np.isfinite(font_size) or font_size <= 0:
        return []
    x, y, width, height = rectangle
    page_height, page_width = source.shape[:2]
    padding = font_size * 8
    left, top = max(0, int(x - padding)), max(0, int(y - padding))
    right = min(page_width, int(np.ceil(x + width + padding)))
    bottom = min(page_height, int(np.ceil(y + height + padding)))
    if right <= left or bottom <= top:
        return []
    patch = source[top:bottom, left:right]
    scale = min(1.0, 24 / font_size, 640 / max(patch.shape[:2]))
    patch = cv2.resize(patch, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    size = font_size * scale
    ink = (cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY) < 150).astype(np.uint8) * 255
    if text_mask is not None:
        glyphs = cv2.resize(text_mask[top:bottom, left:right], (ink.shape[1], ink.shape[0]), interpolation=cv2.INTER_NEAREST)
        ink[cv2.dilate(glyphs, np.ones((3, 3), np.uint8)) > 0] = 0
    else:
        x1, y1 = max(0, int((x-left)*scale)), max(0, int((y-top)*scale))
        x2, y2 = int(np.ceil((x+width-left)*scale)), int(np.ceil((y+height-top)*scale))
        ink[y1:y2, x1:x2] = 0
    fragments = short_fragments(ink, size)
    contours: list[np.ndarray] = []
    for diameter in sorted({max(3, int(np.ceil(size * factor)) | 1) for factor in (.4, .6, .8, 1.0)}):
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (diameter, diameter))
        barrier = cv2.dilate(ink, kernel)
        for hole in enclosed_holes(barrier, fragments, size):
            # A conservative approximation stays inside the observed border.
            inset = max(2, int(np.ceil(size * .12)))
            recovery = max(1, diameter - inset * 2)
            interior = cv2.dilate(hole, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (recovery, recovery)))
            outlines, _ = cv2.findContours(interior, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            contours.extend(np.rint(contour / scale + [left, top]).astype(np.int32) for contour in outlines)
    return contours


def short_fragments(ink: np.ndarray, font_size: float) -> np.ndarray:
    """Exclude continuous artwork strokes and glyph-sized solid components."""
    _, labels, stats, _ = cv2.connectedComponentsWithStats(ink, 8)
    lengths = np.maximum(stats[:, cv2.CC_STAT_WIDTH], stats[:, cv2.CC_STAT_HEIGHT])
    keep = (lengths <= max(6, font_size * 1.25)) & (stats[:, cv2.CC_STAT_AREA] <= max(12, font_size ** 2 * .7))
    keep[0] = False
    return keep[labels].astype(np.uint8) * 255


def enclosed_holes(barrier: np.ndarray, ink: np.ndarray, font_size: float) -> list[np.ndarray]:
    contours, hierarchy = cv2.findContours(barrier, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    if hierarchy is None:
        return []
    holes: list[np.ndarray] = []
    for contour, relation in zip(contours, hierarchy[0]):
        if relation[3] < 0 or cv2.contourArea(contour) < font_size ** 2:
            continue
        x, y, width, height = cv2.boundingRect(contour)
        if x <= 1 or y <= 1 or x + width >= ink.shape[1]-1 or y + height >= ink.shape[0]-1:
            continue
        hole = np.zeros(ink.shape, np.uint8)
        cv2.drawContours(hole, [contour], -1, 255, -1)
        band_size = max(3, int(np.ceil(font_size)) | 1)
        band = cv2.dilate(hole, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (band_size, band_size)))
        observed = cv2.bitwise_and(ink, band)
        fragments, _ = cv2.connectedComponents(observed, 8)
        if fragments >= 7:
            holes.append(hole)
    return holes
