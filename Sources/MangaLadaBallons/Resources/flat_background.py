"""Use measured solid backgrounds before requesting neural text removal."""
import cv2
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
        background = _measured_background(crop, ink)
        output, unresolved = result[top:bottom, left:right], pending[top:bottom, left:right]
        if background is not None:
            output[ink] = background
            unresolved[ink] = 0
            continue
        _prepare_components(crop, ink, output, unresolved)
    return result, pending


def _measured_background(crop, ink, allow_compressed=False):
    evidence, background = ink, crop[~ink]
    if not len(background):
        return None
    if _uniform_color(background, allow_compressed) is None:
        rows, columns = np.nonzero(ink)
        x1, y1 = max(0, columns.min() - 3), max(0, rows.min() - 3)
        x2, y2 = min(ink.shape[1], columns.max() + 4), min(ink.shape[0], rows.max() + 4)
        evidence = ink[y1:y2, x1:x2]
        background = crop[y1:y2, x1:x2][~evidence]
    if len(background) < max(32, evidence.size * .2):
        return None
    return _uniform_color(background, allow_compressed)


def _uniform_color(background: np.ndarray, allow_compressed: bool) -> np.ndarray | None:
    if not len(background):
        return None
    reference = np.median(background, axis=0)
    if np.max(np.ptp(background.astype(np.int16), axis=0)) <= 2:
        return reference.astype(np.uint8)
    if not allow_compressed:
        return None
    # JPEG ringing is sparse on otherwise clipped white paper. Keep ordinary
    # colour/texture rules strict; require both a dominant bright mode and
    # sufficient near-white samples before using this bounded exception.
    distance = np.abs(background.astype(np.float32) - reference).max(axis=1)
    compressed_paper = reference.min() >= 250 and (distance <= 2).mean() >= .8 and (background.min(axis=1) >= 240).mean() >= .9
    return reference.astype(np.uint8) if compressed_paper else None


def _prepare_components(crop, ink, output, unresolved):
    """Measure each confirmed ink component when artwork splits a text line.

    Use three-pixel surroundings with the same strict colour/evidence test.
    Only a dominant near-white component background admits sparse JPEG ringing.
    A nearby frame cannot contaminate the background of distant letters, while
    ink touching a gradient or another colour remains pending for LaMa.
    """
    _, labels, stats, _ = cv2.connectedComponentsWithStats(ink.astype(np.uint8), 8)
    height, width = ink.shape
    for index, (x, y, w, h, _) in enumerate(stats[1:], 1):
        left, top = max(0, x - 3), max(0, y - 3)
        right, bottom = min(width, x + w + 3), min(height, y + h + 3)
        area = np.s_[top:bottom, left:right]
        background = _measured_background(crop[area], ink[area], allow_compressed=True)
        if background is None:
            continue
        confirmed = labels[area] == index
        output[area][confirmed] = background
        unresolved[area][confirmed] = 0
