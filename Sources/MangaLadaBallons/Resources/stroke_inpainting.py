"""Small, confirmed glyph holes use local interpolation before neural inpainting."""
import cv2
import numpy as np


def prepare_thin_strokes(base: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return repaired pixels and the mask still requiring LaMa.

    The caller owns glyph recognition and outline protection. This stage never
    expands that permission: only interior components with a maximum hole
    radius of five pixels use Telea's three-pixel neighbourhood. Wide holes and
    image-edge components retain their original mask for the neural painter.
    No input or pixel outside the approved mask is changed.
    """
    if base.dtype != np.uint8 or mask.dtype != np.uint8:
        raise ValueError("Stroke images and mask must use uint8 pixels")
    if base.ndim != 3 or base.shape[2] != 3 or mask.shape != base.shape[:2] or not mask.size:
        raise ValueError("Stroke image and mask dimensions differ or are empty")
    result, pending = base.copy(), mask.copy()
    if not mask.any():
        return result, pending
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    distance = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    eligible = np.zeros(count, dtype=bool)
    height, width = mask.shape
    for index, (x, y, w, h, _) in enumerate(stats[1:], 1):
        if x == 0 or y == 0 or x + w == width or y + h == height:
            continue
        local = np.s_[y:y + h, x:x + w]
        if distance[local][labels[local] == index].max() <= 5:
            eligible[index] = True
    selected = eligible[labels]
    if not selected.any():
        return result, pending
    # Every approved pixel is unknown to Telea, not only the thin holes: a wide
    # glyph left for LaMa must not bleed its ink into a neighbouring thin stroke.
    # Telea reads a three-pixel neighbourhood, so a small margin around the
    # selected holes sees every pixel that can influence them.
    rows, columns = np.nonzero(selected)
    margin = 8
    top, bottom = max(0, rows.min() - margin), min(height, rows.max() + margin + 1)
    left, right = max(0, columns.min() - margin), min(width, columns.max() + margin + 1)
    window = np.s_[top:bottom, left:right]
    candidate = cv2.inpaint(np.ascontiguousarray(base[window]), np.ascontiguousarray(mask[window]), 3, cv2.INPAINT_TELEA)
    chosen = selected[window]
    result[window][chosen] = candidate[chosen]
    pending[selected] = 0
    return result, pending
