"""Recognition-only decisions for decorated Japanese crops. No translation or erasure."""
from dataclasses import dataclass
from typing import Callable, Literal
import unicodedata
import cv2
import numpy as np
from text_region_geometry import validate_bgr_image


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


def repeated_lettering(text: str) -> bool:
    """A repeated short kana unit needs the contrast view too; repetition counts are fragile."""
    value = text.strip("!?！？。、…~〜")
    return repeated_unit(value) is not None


def repeated_unit(value: str) -> str | None:
    """Return the shortest repeated kana unit without discarding any content."""
    if not all("\u3041" <= char <= "\u3096" or "\u30a1" <= char <= "\u30fa" or char == "ー" for char in value):
        return None
    return next((value[:length] for length in range(1, 5)
                 if len(value) >= length*3 and len(value) % length == 0
                 and value == value[:length]*(len(value)//length)), None)


def crop_variants(crop: np.ndarray) -> list[np.ndarray]:
    """Keep aspect ratio; add edge-colour padding and a separate polarity-normalized view."""
    validate_bgr_image(crop)
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

    A third view is read when the first two disagree or contain repeated short kana. Altered views
    must corroborate the source reading; shared preprocessing mistakes cannot overrule it. Never
    accept empty/non-Japanese results or collapse repeated letters to manufacture agreement.
    Model failures propagate to the caller; a disagreement preserves all readings.
    """
    variants = crop_variants(crop)
    gray = cv2.cvtColor(variants[0], cv2.COLOR_BGR2GRAY)
    if int(gray.max()) - int(gray.min()) < 12:
        return LetteringReading("blank", None, ())
    readings = [recognize(view).strip() for view in variants[:2]]
    first, second = map(normalized_reading, readings)
    if first == second and japanese_reading(first) and not repeated_lettering(first):
        return LetteringReading("consistent", first, tuple(readings))
    readings.append(recognize(variants[2]).strip())
    confirmations = sum(normalized_reading(text) == first for text in readings)
    agreed = japanese_reading(first) and confirmations >= (3 if repeated_lettering(first) else 2)
    return LetteringReading("consistent" if agreed else "needsReview", first if agreed else None, tuple(readings))
