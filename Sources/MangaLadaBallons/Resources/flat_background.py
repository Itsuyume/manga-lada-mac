"""Use measured solid backgrounds before requesting neural text removal."""
import numpy as np


def prepare_flat_backgrounds(source: np.ndarray, base: np.ndarray, mask: np.ndarray,
                            boxes: list[list[int]]) -> tuple[np.ndarray, np.ndarray]:
    """Return a cleaned copy and the unresolved ink mask; inputs remain unchanged.

    Only masked pixels with sufficient uniform, unmasked evidence around the
    ink footprint are filled. Textures, gradients and fully masked crops stay pending for LaMa.
    The separate base supports pages whose other text has already been removed.
    """
    if source.dtype != np.uint8 or base.dtype != np.uint8 or mask.dtype != np.uint8:
        raise ValueError("Text-background images and mask must use uint8 pixels")
    if source.ndim != 3 or source.shape[2] != 3 or base.shape != source.shape or mask.shape != source.shape[:2]:
        raise ValueError("Text-background image and mask dimensions differ")
    height, width = mask.shape
    for left, top, right, bottom in boxes:
        if not all(isinstance(n, (int, np.integer)) for n in (left, top, right, bottom)):
            raise ValueError("Text-background bounds must use integer pixels")
        if not 0 <= left < right <= width or not 0 <= top < bottom <= height:
            raise ValueError("Text-background bounds escape the image")
    result, pending = base.copy(), mask.copy()
    for left, top, right, bottom in boxes:
        crop = source[top:bottom, left:right]
        ink = mask[top:bottom, left:right] > 0
        if not ink.any():
            continue
        evidence, background = ink, crop[~ink]
        if not len(background):
            continue
        if np.max(np.ptp(background.astype(np.int16), axis=0)) > 2:
            rows, columns = np.nonzero(ink)
            x1, y1 = max(0, columns.min() - 3), max(0, rows.min() - 3)
            x2, y2 = min(ink.shape[1], columns.max() + 4), min(ink.shape[0], rows.max() + 4)
            # Exclude distant balloon edges, but retain all colors within the
            # glyph footprint and its immediate surround as evidence.
            evidence = ink[y1:y2, x1:x2]
            background = crop[y1:y2, x1:x2][~evidence]
        if len(background) < max(32, evidence.size * .2):
            continue
        if np.max(np.ptp(background.astype(np.int16), axis=0)) > 2:
            continue
        result[top:bottom, left:right][ink] = np.median(background, axis=0).astype(np.uint8)
        pending[top:bottom, left:right][ink] = 0
    return result, pending
