"""Behavior checks for optically grounded effects; no neural-model mocks."""
from copy import deepcopy
from pathlib import Path
import json
import sys

import numpy as np

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "Sources/MangaLadaBallons/Resources"))
from optical_effects import plan_effects, confirmed_effects, effect_mask

catalog = json.loads((root / "Sources/MangaLadaCore/Resources/sound-effect-lexicon.json").read_text())
sources = {source for entry in catalog["entries"] for source in entry["sources"]}
patterns = catalog["recognitionPatterns"]


def region(identity, text="カチッ", x=.3, y=.4, w=.28, h=.08, confidence=.5):
    return {"id": identity, "originalText": text, "translatedText": "", "confidence": confidence,
            "box": {"x": x, "y": y, "width": w, "height": h}}


def plan(blocks, observations):
    before = deepcopy((blocks, observations))
    result = plan_effects(blocks, observations, sources, patterns)
    assert (blocks, observations) == before, "Planning changed input OCR, identity or geometry"
    return result


def run():
    assert plan([], []) == ([], []), "Empty OCR created effect regions"
    for confidence in [float("nan"), float("inf"), -.1, 1.1]:
        try:
            plan([], [region("bad", confidence=confidence)])
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid optical confidence was silently accepted")
    assert plan([], [region("weak", confidence=.29)]) == ([], []), "Weak evidence erased artwork"
    for coordinates in [dict(x=-.1), dict(y=-.1), dict(w=0), dict(h=-.1), dict(x=.9), dict(y=.99),
                        dict(x=float("nan")), dict(h=float("inf"))]:
        try:
            plan_effects([], [region("bad", **coordinates)], sources, patterns)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid or off-page optical rectangle was accepted")
    for text in ["", "ナナ", "HELLO", "あっ", "カチッと音がした"]:
        assert plan([], [region("unknown", text)]) == ([], []), "Name/dialogue/partial word became an automatic effect"
    missing, matching = plan([], [region("new")])
    assert len(missing) == 1 and missing[0]["id"] == "new" and not matching, "Independently located effect was lost"
    assert confirmed_effects(missing, []) == [], "Missing crop OCR was treated as verified"
    assert confirmed_effects(missing, [region("new", "カチャッ")]) == [], "Disagreeing OCR erased unverified text"
    assert confirmed_effects(missing, [region("new", "")]) == [], "Empty crop OCR became verified text"
    assert confirmed_effects(missing, [region("foreign")]) == [], "Another crop identity verified the proposal"
    try:
        confirmed_effects(missing, [region("new"), region("new")])
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate crop identities were silently merged")
    accepted = confirmed_effects(missing, [region("new", "カチッ。")])
    assert accepted == missing, "Matching crop verification lost native location or identity"
    assert len(plan([], [region("a"), region("b")])[0]) == 1, "Overlapping native observations duplicated effects"
    existing = region("stable", w=.2)
    missing, matching = plan([existing], [region("native")])
    assert not missing and len(matching) == 1, "Existing effect was duplicated instead of widening its erase mask"
    assert matching[0]["box"]["width"] == .28 and existing["box"]["width"] == .2, "Native glyph extent changed stored placement"
    assert plan([region("speech", "こんにちは", w=.2)], [region("native")]) == ([], []), "Effect proposal replaced overlapping dialogue"
    manual = dict(existing, userDefinedBounds=existing["box"])
    assert plan([manual], [region("native")]) == ([], []), "Automatic mask crossed a manual review boundary"
    manual = dict(existing, userDefinedTextKind=True)
    assert plan([manual], [region("native")]) == ([], []), "Automatic effect replaced a reviewed kind"
    assert plan([existing, region("overlap", w=.2)], [region("native")]) == ([], []), "Ambiguous location was accepted"
    _, voiced = plan([region("old", "バタンパタン", w=.2)], [region("native", "バタンバタン")])
    assert len(voiced) == 1, "Dakuten OCR disagreement prevented cleanup of the same located glyphs"
    assert confirmed_effects([region("new", "バタンバタン")], [region("new", "バタンパタン")]) == [], "Fuzzy OCR created a new region"
    caption = region("caption", "雷が近づいてきた。", w=.2)
    caption["textKind"] = "caption"
    missing, matching_caption = plan([caption], [region("native", "雷が近づいてきた。")])
    assert not missing and len(matching_caption) == 1, "Confirmed caption extent left terminal punctuation behind"
    assert caption["textKind"] == "caption" and caption["box"]["width"] == .2, "Caption mask extension changed kind or placement"
    assert plan([caption], [region("native", "雷が遠ざかってきた。")]) == ([], []), "Different sentence widened a mask"
    assert plan([], [region("native", "雷が近づいてきた。")]) == ([], []), "Unmatched caption was added as an effect"
    assert plan([region("empty", "")], [region("native", "")]) == ([], []), "Empty strings confirmed an erase region"
    reviewed = dict(caption, userDefinedBounds=caption["box"])
    assert plan([reviewed], [region("native", caption["originalText"])]) == ([], []), "Caption cleanup crossed manual bounds"
    check_masks(matching)
    print("Optical effect checks passed: missing effects, dual OCR agreement, clipped glyph extent, duplicate/weak/invalid evidence, manual/dialogue protection, bounded dark/light masks, source/art preservation")


def check_masks(regions):
    image = np.full((1000, 1000, 3), 240, np.uint8)
    for left, right in [(308, 348), (398, 438), (548, 568)]:
        image[408:472, left:right] = 0
    image[380:500, 605:610] = 0  # Nearby art outside the verified optical extent.
    before = image.copy()
    mask, boxes = effect_mask(image, regions)
    assert np.all(mask[408:472, 548:568] == 255), "Mask left the clipped last character behind"
    assert not mask[380:500, 605:610].any(), "Mask erased adjacent artwork"
    assert len(boxes) == 1 and boxes[0][2] < 605, "Erase extent escaped the verified optical region"
    assert np.array_equal(image, before), "Mask generation changed source pixels"
    inverse, _ = effect_mask(255 - image, regions)
    assert np.array_equal(mask, inverse), "White lettering on dark background was not selected"
    empty, bounds = effect_mask(image, [])
    assert not empty.any() and not bounds, "Empty effects altered the page"
    try:
        effect_mask(np.full_like(image, 240), regions)
    except ValueError:
        pass
    else:
        raise AssertionError("A blank area silently became an erase rectangle")


if __name__ == "__main__":
    run()
