"""OCR selection and review metadata at the external recognizer boundary."""
from typing import Callable, Literal
import numpy as np
from lettering_ocr import read_lettering, normalized_reading

OCRBackend = Literal["manga", "hayai", "hayai-detected"]


def validate_backend(value: str) -> OCRBackend:
    if value not in ("manga", "hayai", "hayai-detected"):
        raise ValueError("Unknown Japanese OCR backend")
    return value


def recognize_region(crop: np.ndarray, recognize: Callable[[np.ndarray], str], backend: OCRBackend) -> dict:
    validate_backend(backend)
    if backend == "manga":
        text = recognize(crop).strip()
        if not text:
            raise ValueError("Manga OCR returned empty text for a detected region")
        return {"originalText": text, "confidence": 0}
    reading = read_lettering(crop, recognize)
    if reading.status == "consistent":
        return {"originalText": reading.text, "confidence": 0}
    candidates = list(dict.fromkeys(normalized_reading(text) for text in reading.readings if text.strip()))
    return {"originalText": candidates[0] if candidates else "", "confidence": 0,
            "recognitionAlternatives": candidates}
