"""Local text-kind hints at the OCR boundary; translation wording stays untouched."""
import re
import unicodedata

# Only unambiguous common sound forms are hints. Kana alone also includes names,
# replies and dialogue; unknown words remain available to the translation model.
SOUND_EFFECT = re.compile(
    r"(?:ザ[アァー]{1,6}ッ?|([ドゴガ])\1{1,7}|"
    r"(?:(?:[ドゴ]ン|[ドゴガ]ーン|バタン|カチッ|ガチャ[ンッ]?|ゴロゴロ|パチパチ|ピ[ッー])){1,3})"
)


def classify_text_kind(block: dict) -> str | None:
    existing = block.get("textKind")
    if block.get("userDefinedTextKind") is True or existing == "title":
        return existing
    shape = block.get("balloonShape")
    if shape is not None:
        return "caption" if rectangular_enclosure(shape) else existing
    text = unicodedata.normalize("NFKC", block["originalText"]).strip(" \t\r\n.!?。…・")
    if SOUND_EFFECT.fullmatch(text):
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
