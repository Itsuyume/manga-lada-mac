"""Recognition-only decisions for decorated Japanese crops. No translation or erasure."""
from collections import Counter
from dataclasses import dataclass
from typing import Callable, Literal
import unicodedata
import cv2
import numpy as np


@dataclass(frozen=True)
class LetteringReading:
    status: Literal["blank", "consistent", "needsReview"]
    text: str | None
    readings: tuple[str, ...]


def normalized_reading(text: str) -> str:
    """Compare kana widths and spaces without deleting repeats, small kana or masks."""
    return "".join(unicodedata.normalize("NFKC", text).split())


def japanese_reading(text: str) -> bool:
    return bool(text) and any("\u3041" <= char <= "\u3096" or "\u30a1" <= char <= "\u30fa"
                             or "\u3400" <= char <= "\u9fff" for char in text)


def crop_variants(crop: np.ndarray) -> list[np.ndarray]:
    """Keep aspect ratio; add edge-colour padding and a separate polarity-normalized view."""
    if not isinstance(crop, np.ndarray) or crop.dtype != np.uint8 or crop.ndim != 3 or crop.shape[2] != 3:
        raise ValueError("Expected a uint8 BGR lettering crop")
    if min(crop.shape[:2]) < 2:
        raise ValueError("Lettering crop must have at least two pixels on each axis")
    height, width = crop.shape[:2]
    scale = min(1., 1600/max(height, width))
    source = cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA) if scale < 1 else crop.copy()
    edges = np.concatenate([source[0], source[-1], source[:, 0], source[:, -1]])
    color = tuple(int(value) for value in np.median(edges, axis=0))
    padding = max(8, round(min(source.shape[:2]) * .15))
    padded = cv2.copyMakeBorder(source, padding, padding, padding, padding, cv2.BORDER_CONSTANT, value=color)
    gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    if np.median(edges) < 128:
        binary = 255-binary
    contrasted = cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)
    contrasted = cv2.copyMakeBorder(contrasted, padding, padding, padding, padding,
                                   cv2.BORDER_CONSTANT, value=(255, 255, 255))
    return [source, padded, contrasted]


def read_lettering(crop: np.ndarray, recognize: Callable[[np.ndarray], str]) -> LetteringReading:
    """Two matching views are evidence, not a calibrated accuracy probability.

    A third view is read only when the first two disagree. Never majority-vote
    empty/non-Japanese results or collapse repeated letters to manufacture agreement.
    Model failures propagate to the caller; a disagreement preserves all readings.
    """
    variants = crop_variants(crop)
    gray = cv2.cvtColor(variants[0], cv2.COLOR_BGR2GRAY)
    if int(gray.max()) - int(gray.min()) < 12:
        return LetteringReading("blank", None, ())
    readings = [recognize(view).strip() for view in variants[:2]]
    first, second = map(normalized_reading, readings)
    if first == second and japanese_reading(first):
        return LetteringReading("consistent", first, tuple(readings))
    readings.append(recognize(variants[2]).strip())
    counts = Counter(normalized_reading(text) for text in readings)
    agreed = [text for text, count in counts.items() if count >= 2 and japanese_reading(text)]
    return LetteringReading("consistent" if agreed else "needsReview", agreed[0] if agreed else None, tuple(readings))
