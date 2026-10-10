"""Relative foreground contrast shared by glyph erasure and punctuation evidence."""
import cv2
import numpy as np


def foreground_mask(gray: np.ndarray, background: float | None = None) -> np.ndarray:
    """Select the threshold class opposite the measured paper, not absolute 127.

    Black ink remains dark foreground on mid-tone coloured paper; white ink
    remains bright foreground even when its background exceeds mid-grey.
    """
    if not isinstance(gray, np.ndarray) or gray.dtype != np.uint8 or gray.ndim != 2:
        raise ValueError("Text contrast requires a uint8 grayscale image")
    if not gray.size:
        return np.zeros_like(gray)
    paper = float(np.median(gray)) if background is None else background
    if not np.isfinite(paper) or not 0 <= paper <= 255:
        raise ValueError("Text background intensity must be finite and within 0...255")
    threshold, bright = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    return cv2.bitwise_not(bright) if paper > threshold else bright
