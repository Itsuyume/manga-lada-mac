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
    holes = selected.astype(np.uint8) * 255
    candidate = cv2.inpaint(base, holes, 3, cv2.INPAINT_TELEA)
    result[selected] = candidate[selected]
    pending[selected] = 0
    return result, pending
