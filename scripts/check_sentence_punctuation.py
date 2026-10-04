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
        for dark in [False, True]:
            check_multiline(vertical, dark, False)
            check_multiline(vertical, dark, True)
        check_multiline(vertical, False, True, scale=10)
    check_rejections()
    check_multiline_rejections()
    print("Sentence punctuation passed: empty/invalid input, OCR disagreement, light/dark vertical/horizontal and multiline endings, manual/ambiguous/outside regions, source and artwork preservation")


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
    large = cv2.resize(image, None, fx=10, fy=10, interpolation=cv2.INTER_NEAREST)
    large_block = dict(block, detectedFontSize=320)
    candidates = sentence_end_candidates(large, [large_block])
    assert len(candidates) == 1
    mask, _ = glyph_mask(large, [candidate.box for candidate in candidates], bounded=True)
    assert mask[cy*10-40:cy*10+41, cx*10-40:cx*10+41].any()
    large[cy*10:cy*10+3, cx*10+65:cx*10+68] = 0
    assert sentence_end_candidates(large, [large_block]) == [], "High-resolution mask could recruit nearby artwork"


def multiline_fixture(vertical, dark, short_final):
    image, block, _ = fixture()
    image[50:165, 70:175] = 240
    image[60:80, 80:102] = 0
    if not short_final:
        image[92:115, 80:102] = 0
    image[60:80, 140:162] = 0
    image[92:115, 140:162] = 0
    center = (87, 102 if short_final else 137)
    cv2.circle(image, center, 4, (0, 0, 0), 2)
    block.update(box=dict(x=75/240, y=55/240, width=92/240, height=67/240), originalText="ゆっくりはがして")
    if not vertical:
        image = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
        box = block["box"]
        block.update(box=dict(x=box["y"], y=1-box["x"]-box["width"], width=box["height"], height=box["width"]),
                     sourceIsVertical=False)
        center = (center[1], 239-center[0])
        block["balloonShape"] = {"rows": [{"y": y/240, "left": 32/240, "right": 198/240} for y in range(56, 188)]}
    return (255-image if dark else image), block, center


def check_multiline(vertical, dark, short_final, scale=1):
    image, block, (cx, cy) = multiline_fixture(vertical, dark, short_final)
    if scale != 1:
        image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
        block["detectedFontSize"] *= scale
        cx, cy = cx * scale, cy * scale
    original, source = deepcopy(block), image.copy()
    candidates = sentence_end_candidates(image, [block])
    assert len(candidates) == 1, (vertical, dark, short_final, "Multiline period was not selected")
    assert confirms_sentence_end(candidates[0], "ゆっくりはがして。")
    assert not confirms_sentence_end(candidates[0], "ゆっくりはがして"), "A pixel ring alone confirmed punctuation"
    mask, boxes = glyph_mask(image, [candidate.box for candidate in candidates], bounded=True)
    assert mask[cy-4*scale:cy+5*scale, cx-4*scale:cx+5*scale].any(), "The sentence-final period was missed"
    allowed = np.zeros_like(mask)
    allowed[cy-12*scale:cy+13*scale, cx-12*scale:cx+13*scale] = 255
    assert not mask[allowed == 0].any(), "A letter, neighboring column, or balloon border was selected"
    assert len(boxes) == 1 and block == original and np.array_equal(image, source)


def check_multiline_rejections():
    image, block, (cx, cy) = multiline_fixture(True, False, True)
    first_column_only = image.copy()
    first_column_only[cy-6:cy+7, cx-6:cx+7] = 240
    cv2.circle(first_column_only, (147, 137), 4, (0, 0, 0), 2)
    assert sentence_end_candidates(first_column_only, [block]) == [], "A non-final column was used"
    nonterminal = image.copy(); nonterminal[117:121, 80:102] = 0
    assert sentence_end_candidates(nonterminal, [block]) == [], "A ring before more text was selected"
    merged = image.copy(); merged[61:80, 80:163] = 0
    assert sentence_end_candidates(merged, [block]) == [], "Unseparated text columns were guessed"
    only_ring = image.copy(); only_ring[50:86, 70:110] = 240
    assert sentence_end_candidates(only_ring, [block]) == [], "A ring without a preceding last-column character was selected"
    other = dict(block, id="other", box=dict(x=(cx-7)/240, y=(cy-7)/240, width=14/240, height=14/240))
    assert sentence_end_candidates(image, [block, other]) == [], "An overlapping region's glyph was selected"


if __name__ == "__main__":
    run()
