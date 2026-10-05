"""Read-only crop preparation. Candidate geometry never becomes an erase mask."""
from dataclasses import asdict
from typing import Callable
import numpy as np
from balloon_candidates import balloon_candidates
from lettering_ocr import read_lettering


def lettering_crops(image: np.ndarray, mode: str) -> list[tuple[tuple[int, int, int, int], np.ndarray]]:
    if mode not in ("scan", "crop"):
        raise ValueError("Lettering mode must be scan or crop")
    if not isinstance(image, np.ndarray) or image.ndim != 3 or image.shape[2] != 3 or min(image.shape[:2]) < 2 or image.dtype != np.uint8:
        raise ValueError("Expected a nonempty uint8 BGR image")
    height, width = image.shape[:2]
    if mode == "crop":
        return [((0, 0, width, height), image.copy())]
    result = []
    for candidate in balloon_candidates(image, [], connected_lettering=True):
        x1, y1, x2, y2 = candidate.bounds
        crop = image[y1:y2, x1:x2].copy()
        background_pixels = crop[(candidate.interior > 0) & (candidate.ink == 0)]
        if not len(background_pixels):
            continue
        crop[candidate.interior == 0] = np.median(background_pixels, axis=0).astype(np.uint8)
        result.append((candidate.bounds, crop))
    return result


def inspect_lettering_regions(image: np.ndarray, recognize: Callable[[np.ndarray], str], mode: str = "scan") -> list[dict]:
    return [dict(bounds=bounds, **asdict(read_lettering(crop, recognize))) for bounds, crop in lettering_crops(image, mode)]
