"""Read-only crop preparation. Candidate geometry never becomes an erase mask."""
from dataclasses import asdict
from typing import Callable
import numpy as np
from balloon_candidates import BalloonCandidate, balloon_candidates
from lettering_ocr import read_lettering
from text_region_geometry import validate_bgr_image
from text_detection import TextDetection, contact_crop_bounds


def lettering_crops(image: np.ndarray, mode: str) -> list[tuple[tuple[int, int, int, int], np.ndarray]]:
    if mode not in ("scan", "crop"):
        raise ValueError("Lettering mode must be scan or crop")
    validate_bgr_image(image)
    height, width = image.shape[:2]
    if mode == "crop":
        return [((0, 0, width, height), image.copy())]
    result = []
    for candidate in balloon_candidates(image, [], connected_lettering=True):
        result.append((candidate.bounds, candidate_crop(image, candidate, candidate.bounds)))
    return result


def candidate_crop(image: np.ndarray, candidate: BalloonCandidate, bounds: tuple[int, int, int, int]) -> np.ndarray:
    """Use the observed balloon colour beyond its interior, without changing the source."""
    x1, y1, x2, y2 = candidate.bounds
    patch = image[y1:y2, x1:x2]
    background = patch[(candidate.interior > 0) & (candidate.ink == 0)]
    if not len(background):
        raise ValueError("Balloon candidate has no background samples")
    left, top, right, bottom = bounds
    crop = np.empty((bottom-top, right-left, 3), np.uint8)
    crop[:] = np.median(background, axis=0).astype(np.uint8)
    ix1, iy1, ix2, iy2 = max(left, x1), max(top, y1), min(right, x2), min(bottom, y2)
    inside = candidate.interior[iy1-y1:iy2-y1, ix1-x1:ix2-x1] > 0
    crop[iy1-top:iy2-top, ix1-left:ix2-left][inside] = image[iy1:iy2, ix1:ix2][inside]
    return crop


def inspect_lettering_regions(image: np.ndarray, recognize: Callable[[np.ndarray], str], mode: str = "scan") -> list[dict]:
    return [dict(bounds=bounds, **asdict(read_lettering(crop, recognize))) for bounds, crop in lettering_crops(image, mode)]


def inspect_detected_lettering(image: np.ndarray, recognize: Callable[[np.ndarray], str],
                               detect: Callable[[np.ndarray], list[TextDetection]], limit: int = 24) -> list[dict]:
    """Independent of CTD and closed balloon outlines. Preserve every deferred proposal."""
    validate_bgr_image(image)
    if type(limit) is not int or not 0 <= limit <= 40:
        raise ValueError("OCR region limit must be between zero and forty")
    proposals = detect(image)
    result = []
    for index, proposal in enumerate(proposals):
        bounds = contact_crop_bounds(proposal, proposals, image.shape[1::-1])
        evidence = dict(bounds=bounds, detectedBounds=proposal.bounds, detectionScore=proposal.score,
                        detectionHint=proposal.hint)
        if index >= limit:
            result.append(dict(**evidence, status="deferred", text=None, readings=[]))
            continue
        x1, y1, x2, y2 = bounds
        reading = read_lettering(image[y1:y2, x1:x2].copy(), recognize)
        result.append(dict(**evidence, **asdict(reading)))
    return result
