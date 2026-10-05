"""Protect observed source balloon boundaries before any background reconstruction."""
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry


def protect_balloon_outlines(mask: np.ndarray, regions: list[dict], geometry: BalloonGeometry) -> np.ndarray:
    """Remove boundary bands from a detector mask; never add erase permission.

    The existing enclosure validator owns source evidence. A missing enclosure
    gives no new geometry, and free artwork/text keeps its detector mask. Full
    pixel contours are used before lobe partitioning or row sampling, so an
    internal line dividing two dialogue columns is not treated as a border.
    """
    if mask.dtype != np.uint8 or mask.shape != (geometry.height, geometry.width):
        raise ValueError("Balloon erase mask does not match the source page")
    result = mask.copy()
    for region in regions:
        font_size = region["detectedFontSize"]
        contour = geometry.enclosure(region["box"], font_size)
        if contour is None:
            continue
        interior, x, y = contour
        # Closing can move a jagged/dashed contour inward by its kernel radius.
        # Include that uncertainty as well as the original stroke/antialiasing.
        margin = geometry.contour_kernel_size(font_size) // 2 + max(2, min(8, int(np.ceil(font_size * .04)))) + 1
        padded = cv2.copyMakeBorder(interior, margin, margin, margin, margin, cv2.BORDER_CONSTANT)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (margin * 2 + 1, margin * 2 + 1))
        band = cv2.dilate(padded, kernel) & ~cv2.erode(padded, kernel)
        left, top = max(0, x - margin), max(0, y - margin)
        right = min(geometry.width, x + interior.shape[1] + margin)
        bottom = min(geometry.height, y + interior.shape[0] + margin)
        offset_x, offset_y = left - x + margin, top - y + margin
        crop = np.s_[offset_y:offset_y + bottom - top, offset_x:offset_x + right - left]
        protected = observed_boundary(geometry.source[top:bottom, left:right], padded[crop], band[crop])
        result[top:bottom, left:right][protected > 0] = 0
    return result


def observed_boundary(source: np.ndarray, interior: np.ndarray, band: np.ndarray) -> np.ndarray:
    """Keep original boundary strokes, without reserving a wide blank margin.

    Closing uncertainty only guides the search. A component must lie mostly on
    that boundary to be protected; a nearby large letter is not clipped merely
    because a few of its pixels enter the search band. Separate dashes qualify
    on their own and retain their original positions.
    """
    gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
    background = np.median(gray[interior > 0])
    outside = gray[interior == 0]
    exterior = np.median(outside) if outside.size else background
    # A darker panel outside a white balloon is not itself a boundary stroke.
    threshold = min(background, exterior) - 30 if background >= 128 else max(background, exterior) + 30
    foreground = gray < threshold if background >= 128 else gray > threshold
    _, labels, stats, _ = cv2.connectedComponentsWithStats(foreground.astype(np.uint8), 8)
    support = np.bincount(labels[band > 0], minlength=len(stats))
    selected = (support >= stats[:, cv2.CC_STAT_AREA] * .5) & (stats[:, cv2.CC_STAT_AREA] >= 2)
    selected[0] = False
    boundary = selected[labels].astype(np.uint8) * 255
    return cv2.dilate(boundary, np.ones((3, 3), np.uint8))
