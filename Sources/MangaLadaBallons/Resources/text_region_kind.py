"""Local text-kind hints at the OCR boundary; translation wording stays untouched."""
import re
import unicodedata
import text_region_geometry as geometry


def normalized_source(text: str) -> str:
    return "".join(unicodedata.normalize("NFKC", text).split()).strip(".!?。…・")


def is_sound_effect(text: str, sources: set[str], patterns: list[str]) -> bool:
    text = normalized_source(text)
    return text in sources or any(re.fullmatch(pattern, text) for pattern in patterns)


def classify_text_kind(block: dict, sound_effect_sources: set[str], sound_effect_patterns: list[str]) -> str | None:
    existing = block.get("textKind")
    if block.get("userDefinedTextKind") is True or existing == "title":
        return existing
    shape = block.get("balloonShape")
    if shape is not None:
        return "caption" if geometry.rectangular_enclosure(shape) else existing
    if is_sound_effect(block["originalText"], sound_effect_sources, sound_effect_patterns):
        return "soundEffect"
    return existing
