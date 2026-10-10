"""Restoration context and work bounds derived from approved pixels, not OCR boxes."""
import cv2
import numpy as np


def reconstruction_mask(mask: np.ndarray) -> np.ndarray:
    """Hide nearby antialiasing from the painter; this grants no erase permission.

    Callers must composite the candidate through the original approved mask.
    The three-pixel context is for the neural painter; local thin-stroke repair
    keeps its own approved mask so unresolved neighbouring ink cannot bleed in.
    """
    validate_mask(mask)
    return cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))


def reconstruction_bounds(mask: np.ndarray) -> list[list[int]]:
    """Cover pending ink with source context, independent of OCR polygons.

    Nearby components share a work window with 64 pixels of surrounding paper.
    Tiny fragments must not send the neural painter a glyph-sized crop. These
    windows never define erase permission; the separate mask still owns that.
    """
    validate_mask(mask)
    windows = cv2.dilate(mask, np.ones((129, 129), np.uint8))
    _, _, stats, _ = cv2.connectedComponentsWithStats(windows, 8)
    return [[int(x), int(y), int(x + width), int(y + height)]
            for x, y, width, height, _ in stats[1:]]


def validate_mask(mask: np.ndarray) -> None:
    if not isinstance(mask, np.ndarray) or mask.dtype != np.uint8 or mask.ndim != 2 or not mask.size:
        raise ValueError("Reconstruction mask must be a nonempty uint8 pixel plane")
