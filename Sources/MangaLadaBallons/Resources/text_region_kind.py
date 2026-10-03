"""Local text-kind hints at the OCR boundary; translation wording stays untouched."""
import re
import unicodedata


def classify_text_kind(block: dict, sound_effect_sources: set[str], sound_effect_patterns: list[str]) -> str | None:
    existing = block.get("textKind")
    if block.get("userDefinedTextKind") is True or existing == "title":
        return existing
    shape = block.get("balloonShape")
    if shape is not None:
        return "caption" if rectangular_enclosure(shape) else existing
    text = unicodedata.normalize("NFKC", block["originalText"]).strip(" \t\r\n.!?。…・")
    if text in sound_effect_sources or any(re.fullmatch(pattern, text) for pattern in sound_effect_patterns):
        return "soundEffect"
    return existing


def rectangular_enclosure(shape: dict) -> bool:
    """Recognized near-rectangular interiors, independent of glyph/background color.

    Use the original contour before connected balloons are partitioned. This does
    not search for new regions or change the placement area.
    """
    rows, bounds = shape["rows"], shape["bounds"]
    width = bounds["width"]
    coverage = sum(row["right"] - row["left"] for row in rows) / (len(rows) * width)
    left_spread = max(row["left"] for row in rows) - min(row["left"] for row in rows)
    right_spread = max(row["right"] for row in rows) - min(row["right"] for row in rows)
    return coverage >= .97 and max(left_spread, right_spread) <= width * .06
