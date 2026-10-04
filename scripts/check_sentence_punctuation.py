"""Behavior checks for bounded, OCR-confirmed sentence-final glyph recovery."""
from copy import deepcopy
import argparse
from pathlib import Path
import sys

import cv2
import numpy as np

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser()
parser.add_argument("--resources", type=Path, default=Path(__file__).resolve().parent.parent / "Sources/MangaLadaBallons/Resources")
sys.path.insert(0, str(parser.parse_args().resources))
from erase_supplemental_text import glyph_mask
from sentence_punctuation import sentence_end_candidates, confirms_sentence_end


def fixture(vertical=True, dark=False):
    image = np.full((240, 240, 3), 240, np.uint8)
    cv2.rectangle(image, (50, 30), (185, 200), (0, 0, 0), 3)
    if vertical:
        image[60:80, 95:118] = 0
        image[92:115, 95:118] = 0
        center, box = (102, 137), dict(x=90/240, y=55/240, width=32/240, height=67/240)
    else:
        image[92:115, 60:80] = 0
        image[92:115, 92:115] = 0
        center, box = (137, 106), dict(x=55/240, y=88/240, width=67/240, height=32/240)
    cv2.circle(image, center, 4, (0, 0, 0), 2)
    shape = {"bounds": dict(x=52/240, y=32/240, width=131/240, height=166/240),
             "rows": [{"y": y/240, "left": 52/240, "right": 183/240} for y in range(32, 199)]}
    block = dict(id="dialogue", box=box, originalText="はい", detectedFontSize=32,
                 sourceIsVertical=vertical, rotationDegrees=0, textKind="dialogue", balloonShape=shape)
    return (255-image if dark else image), block, center


def expect_error(image, blocks):
    try:
        sentence_end_candidates(image, blocks)
    except (ValueError, TypeError):
        return
    raise AssertionError("Invalid candidate request was silently accepted")


def run():
    image, block, center = fixture()
    before, original = image.copy(), deepcopy(block)
    assert sentence_end_candidates(image, []) == []
    assert sentence_end_candidates(np.full_like(image, 240), [block]) == []
    expect_error(image, None)
    for value in [0, -2, float("nan"), float("inf")]:
        broken = deepcopy(block); broken["detectedFontSize"] = value
        expect_error(image, [broken])
    for value in [-.1, float("nan"), 2]:
        broken = deepcopy(block); broken["box"]["x"] = value
        expect_error(image, [broken])
    for value in [float("nan"), float("inf")]:
        broken = deepcopy(block); broken["rotationDegrees"] = value
        expect_error(image, [broken])
    for key, value in [("userDefinedBounds", block["box"]), ("userDefinedTextKind", True),
                       ("userDefinedOriginalText", True), ("textKind", "soundEffect"),
                       ("textKind", "title"), ("balloonShape", None), ("rotationDegrees", 25)]:
        protected = deepcopy(block); protected[key] = value
        assert sentence_end_candidates(image, [protected]) == [], key
    assert sentence_end_candidates(image, [block, dict(block, id="overlap")]) == []
    other = dict(block, id="crossing-line", sourceIsVertical=False,
                 box=dict(x=42/240, y=122/240, width=48/240, height=28/240))
    assert sentence_end_candidates(image, [block, other]) == [], "Two sentences claimed one ring"
    candidates = sentence_end_candidates(image, [block])
    assert len(candidates) == 1 and candidates[0].block_id == "dialogue"
    candidate = candidates[0]
    assert confirms_sentence_end(candidate, "はい。")
    for reply in ["", "はい", "いいえ。", "はい！", "はい。。", "は○。", None]:
        assert not confirms_sentence_end(candidate, reply), reply
    assert sentence_end_candidates(image, [dict(block, originalText="はい。")]) == [], "An existing period cannot prove another ring belongs to this sentence"
    for vertical, box in [(True, dict(x=.4, y=.9, width=.1, height=.1)),
                          (False, dict(x=.9, y=.4, width=.1, height=.1))]:
        assert sentence_end_candidates(image, [dict(block, box=box, sourceIsVertical=vertical)]) == [], "End band exceeded page bounds"
    assert np.array_equal(image, before) and block == original, "Proposal changed original source or geometry"
    for vertical in [True, False]:
        check_pixels(vertical, False)
        check_pixels(vertical, True)
    check_rejections()
    print("Sentence punctuation passed: empty/invalid input, OCR disagreement, light/dark vertical/horizontal glyphs, manual/ambiguous/outside regions, source and artwork preservation")


def check_pixels(vertical, dark):
    image, block, (cx, cy) = fixture(vertical, dark)
    before = image.copy()
    candidates = sentence_end_candidates(image, [block])
    assert len(candidates) == 1, (vertical, dark)
    mask, boxes = glyph_mask(image, [candidate.box for candidate in candidates], bounded=True)
    assert mask[cy-4:cy+5, cx-4:cx+5].any(), "Confirmed period not selected"
    assert not mask[30:201, 47:54].any(), "Balloon border selected"
    assert not mask[55:120, 55:122].any(), "Existing text unexpectedly changed"
    assert not mask[:25].any() and len(boxes) == 1
    assert np.array_equal(image, before), "Mask construction changed the source"


def check_rejections():
    image, block, (cx, cy) = fixture()
    outside = deepcopy(block)
    outside["balloonShape"]["rows"] = [dict(row, right=(cx-2)/240) for row in outside["balloonShape"]["rows"]]
    assert sentence_end_candidates(image, [outside]) == [], "Period outside balloon was selected"
    touching = image.copy(); cv2.line(touching, (cx+4, cy), (cx+30, cy), (0, 0, 0), 2)
    assert sentence_end_candidates(touching, [block]) == [], "Connected artwork became punctuation"
    filled = image.copy(); cv2.circle(filled, (cx, cy), 4, (0, 0, 0), -1)
    assert sentence_end_candidates(filled, [block]) == [], "Solid artwork dot became a Japanese period"
    ambiguous = image.copy(); cv2.circle(ambiguous, (cx+12, cy), 4, (0, 0, 0), 2)
    assert sentence_end_candidates(ambiguous, [block]) == [], "Ambiguous adjacent ring chosen"
    multiline = deepcopy(block); multiline["box"]["width"] = 80/240
    assert sentence_end_candidates(image, [multiline]) == [], "Unsupported multiline crop was guessed"
    large = cv2.resize(image, None, fx=10, fy=10, interpolation=cv2.INTER_NEAREST)
    large_block = dict(block, detectedFontSize=320)
    candidates = sentence_end_candidates(large, [large_block])
    assert len(candidates) == 1
    mask, _ = glyph_mask(large, [candidate.box for candidate in candidates], bounded=True)
    assert mask[cy*10-40:cy*10+41, cx*10-40:cx*10+41].any()
    large[cy*10:cy*10+3, cx*10+65:cx*10+68] = 0
    assert sentence_end_candidates(large, [large_block]) == [], "High-resolution mask could recruit nearby artwork"


if __name__ == "__main__":
    run()
