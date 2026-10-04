"""Reconcile native OCR with manga OCR before any new glyph mask is painted."""
import math
import unicodedata
import text_region_geometry as geometry

from erase_supplemental_text import glyph_mask
from text_region_kind import is_sound_effect, normalized_source


def plan_effects(blocks, observations, sources, patterns):
    """New regions require known effects; matched existing text may widen its ink mask."""
    missing, matching = [], []
    for observation in observations:
        confidence = observation["confidence"]
        if not math.isfinite(confidence) or not 0 <= confidence <= 1:
            raise ValueError("Invalid optical confidence")
        geometry.validate_box(observation["box"])
        if confidence < .3:
            continue
        if any(geometry.overlaps(observation["box"], used["box"]) for used in missing + matching):
            continue
        nearby = [block for block in blocks if geometry.overlaps(observation["box"], block["box"])]
        if not nearby:
            if is_sound_effect(observation["originalText"], sources, patterns):
                missing.append(dict(observation))
            continue
        if len(nearby) != 1:
            continue
        existing = nearby[0]
        if existing.get("userDefinedBounds") is not None or existing.get("userDefinedTextKind") is True:
            continue
        key = glyph_key(existing["originalText"])
        if key and key == glyph_key(observation["originalText"]):
            matching.append(dict(observation))
    return missing, matching


def confirmed_effects(proposals, recognized):
    by_id = {block["id"]: block for block in recognized}
    if len(by_id) != len(recognized):
        raise ValueError("Duplicate crop OCR identities")
    return [dict(proposal) for proposal in proposals
            if proposal["id"] in by_id
            and normalized_source(proposal["originalText"]) == normalized_source(by_id[proposal["id"]]["originalText"])]


def effect_mask(image, effects):
    height, width = image.shape[:2]
    regions = []
    for effect in effects:
        box = effect["box"]
        geometry.validate_box(box)
        pad = max(4, min(box["width"] * width, box["height"] * height) * .12)
        left, top = max(0, box["x"] - pad / width), max(0, box["y"] - pad / height)
        right = min(1, box["x"] + box["width"] + pad / width)
        bottom = min(1, box["y"] + box["height"] + pad / height)
        regions.append({"x": left, "y": top, "width": right - left, "height": bottom - top})
    return glyph_mask(image, regions, bounded=True)


def glyph_key(text):
    """Voicing may disagree while both OCR engines locate the same existing glyphs.

    This key only widens an existing ink mask. New regions require exact agreement.
    """
    return "".join(character for character in unicodedata.normalize("NFKD", normalized_source(text))
                   if character not in "\u3099\u309a" and not character.isspace())
