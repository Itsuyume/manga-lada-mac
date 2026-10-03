"""Reconcile native OCR with manga OCR before any new glyph mask is painted."""
import math
import unicodedata

import numpy as np

from erase_supplemental_text import glyph_mask
from text_region_kind import is_sound_effect, normalized_source


def plan_effects(blocks, observations, sources, patterns):
    missing, matching = [], []
    for observation in observations:
        confidence = observation["confidence"]
        if not math.isfinite(confidence) or not 0 <= confidence <= 1:
            raise ValueError("Invalid optical confidence")
        validate_box(observation["box"])
        if confidence < .3 or not is_sound_effect(observation["originalText"], sources, patterns):
            continue
        if any(overlaps(observation["box"], used["box"]) for used in missing + matching):
            continue
        nearby = [block for block in blocks if overlaps(observation["box"], block["box"])]
        if not nearby:
            missing.append(dict(observation))
            continue
        if len(nearby) != 1:
            continue
        existing = nearby[0]
        if existing.get("userDefinedBounds") is not None or existing.get("userDefinedTextKind") is True:
            continue
        if glyph_key(existing["originalText"]) == glyph_key(observation["originalText"]):
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
        validate_box(box)
        pad = max(4, min(box["width"] * width, box["height"] * height) * .12)
        left, top = max(0, box["x"] - pad / width), max(0, box["y"] - pad / height)
        right = min(1, box["x"] + box["width"] + pad / width)
        bottom = min(1, box["y"] + box["height"] + pad / height)
        regions.append({"x": left, "y": top, "width": right - left, "height": bottom - top})
    return glyph_mask(image, regions, bounded=True)


def restore_flat_backgrounds(original, result, mask, boxes):
    """Replace neural color drift only inside ink masks on measured solid backgrounds.

    Textured/gradient backgrounds remain the neural result. The caller owns result;
    original and mask are read-only. No rectangle is filled in its entirety.
    """
    for left, top, right, bottom in boxes:
        source = original[top:bottom, left:right]
        ink = mask[top:bottom, left:right] > 0
        background = source[~ink]
        if len(background) < max(32, ink.size * .2):
            continue
        if np.max(np.ptp(background.astype(np.int16), axis=0)) > 2:
            continue
        result[top:bottom, left:right][ink] = np.median(background, axis=0).astype(np.uint8)


def glyph_key(text):
    """Voicing may disagree while both OCR engines locate the same existing glyphs.

    This key only widens an existing ink mask. New regions require exact agreement.
    """
    return "".join(character for character in unicodedata.normalize("NFKD", normalized_source(text))
                   if character not in "\u3099\u309a" and not character.isspace())


def validate_box(box):
    x, y, w, h = (box[key] for key in ("x", "y", "width", "height"))
    if not all(math.isfinite(value) for value in (x, y, w, h)) or min(x, y) < 0 or min(w, h) <= 0 or x + w > 1.000001 or y + h > 1.000001:
        raise ValueError("Invalid optical rectangle")


def overlaps(first, second):
    width = max(0, min(first["x"] + first["width"], second["x"] + second["width"]) - max(first["x"], second["x"]))
    height = max(0, min(first["y"] + first["height"], second["y"] + second["height"]) - max(first["y"], second["y"]))
    return width * height > min(first["width"] * first["height"], second["width"] * second["height"]) * .25
