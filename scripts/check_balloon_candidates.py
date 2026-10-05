"""Outline-first proposals: image behavior and external detector contracts."""
from dataclasses import dataclass
from pathlib import Path
import sys
sys.dont_write_bytecode = True
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from balloon_candidates import balloon_candidates
from balloon_recovery import recover_balloons, confirmed_mask, translated_detection


def fixture(dotted=False, dark=False, jagged=False):
    image = np.full((600, 600, 3), 170, np.uint8)
    background = (48, 48, 48) if dark else (215, 224, 247)
    color = (250, 250, 250) if dark else (25, 25, 25)
    if jagged:
        angles = np.linspace(0, 2*np.pi, 40, endpoint=False)
        radii = np.where(np.arange(40) % 2, .88, 1.)
        contour = np.column_stack((200 + 100*radii*np.cos(angles), 200+160*radii*np.sin(angles))).astype(np.int32)
        cv2.fillPoly(image, [contour], background)
        cv2.polylines(image, [contour], True, (20, 20, 20), 2)
    else:
        cv2.ellipse(image, (200, 200), (100, 160), 0, 0, 360, background, -1)
        for angle in range(0, 360, 10 if dotted else 360):
            cv2.ellipse(image, (200, 200), (100, 160), 0, angle, angle+(5 if dotted else 360), (20, 20, 20), 2)
    for y in (130, 180, 230, 280):
        cv2.putText(image, "TEXT", (155, y), cv2.FONT_HERSHEY_SIMPLEX, .65, color, 2, cv2.LINE_AA)
    return image


# Empty, invalid, cap and full-coverage cases come first.
blank = np.full((420, 500, 3), 255, np.uint8)
assert balloon_candidates(blank, []) == []
assert balloon_candidates(fixture(), [], limit=0) == []
for occupied in [[(-1, 0, 10, 20)], [(1, 1, 1, 4)], [(0, 0, 600, 900)]]:
    try:
        balloon_candidates(blank, occupied)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid occupied area accepted")
for dotted, dark, jagged in [(False, False, False), (True, False, False), (False, True, False), (False, False, True)]:
    image = fixture(dotted, dark, jagged)
    before = image.copy()
    for factor in (.6, 1., 1.8):
        scaled = cv2.resize(image, None, fx=factor, fy=factor, interpolation=cv2.INTER_AREA)
        candidates = balloon_candidates(scaled, [])
        assert len(candidates) == 1, (dotted, dark, jagged, factor, [c.bounds for c in candidates])
        c = candidates[0]
        assert c.bounds[0] < 160*factor and c.bounds[2] > 240*factor
        assert np.count_nonzero(c.ink) > 20 and c.interior.shape == c.ink.shape
        occupied = [(int(150*factor), int(100*factor), int(245*factor), int(290*factor))]
        assert balloon_candidates(scaled, occupied) == [], "An already read balloon was proposed again"
    assert np.array_equal(image, before), "Candidate discovery changed source pixels"

empty_balloon = fixture()
cv2.rectangle(empty_balloon, (150, 100), (245, 290), (215, 224, 247), -1)
assert not balloon_candidates(empty_balloon, []), "Empty enclosure was mistaken for text"
open_border = blank.copy()
cv2.ellipse(open_border, (200, 200), (100, 160), 0, 40, 320, (20, 20, 20), 2)
assert not balloon_candidates(open_border, []), "An open border was closed using the crop edge"


@dataclass
class Detection:
    xyxy: list[int]
    lines: list
    _detected_font_size: float = 20


image = fixture()
c = balloon_candidates(image, [])[0]
mask = np.zeros(image.shape[:2], np.uint8)
block = Detection([150, 105, 250, 285], [[[150, 105], [250, 105], [250, 285], [150, 285]]])
local = translated_detection(block, -c.bounds[0], -c.bounds[1])
assert translated_detection(local, *c.bounds[:2]).xyxy == block.xyxy
assert block.xyxy == [150, 105, 250, 285], "Coordinate rebasing changed detector input"
assert confirmed_mask(c, block, c.ink, c.bounds[:2]) is not None
assert confirmed_mask(c, block, np.zeros_like(c.ink), c.bounds[:2]) is None
outside = Detection([0, 0, 400, 400], [])
assert confirmed_mask(c, outside, c.ink, c.bounds[:2]) is None

# A stand-in only at the external detector boundary; recovery/geometry/masks are production code.
calls = []
def no_detection(crop):
    calls.append(crop.shape)
    return np.zeros(crop.shape[:2], np.uint8), []
preserved, regions = recover_balloons(image, mask, [], no_detection)
assert len(calls) == 1 and not regions and np.array_equal(preserved, mask)
calls.clear()
recover_balloons(image, mask, [block], no_detection)
assert not calls, "Fully recognized text made a redundant crop/model request"
prior = [{"id": "kept", "box": dict(x=0.25, y=0.175, width=1/6, height=.3), "originalText": "kept",
          "userDefinedBounds": dict(x=.24, y=.16, width=.2, height=.33)}]
recover_balloons(image, mask, [], no_detection, prior)
assert not calls and prior[0]["originalText"] == "kept", "A manual review triggered duplicate detection"
def confirmed_detection(crop):
    # This fixture's crop origin is (0, 0); the detector's independent mask is returned intact.
    m = np.zeros(crop.shape[:2], np.uint8)
    x1, y1, x2, y2 = c.bounds
    m[y1:y2, x1:x2] = c.ink
    return m, [block]
added, regions = recover_balloons(image, mask, [], confirmed_detection)
assert len(regions) == 1 and regions[0].xyxy == block.xyxy and added.any()
assert not added[:100].any() and not added[290:].any(), "Recovery erased outside confirmed text"
assert regions[0] is not block and block.xyxy == [150, 105, 250, 285]
def broken_detection(crop):
    raise RuntimeError("detector failure")
try:
    recover_balloons(image, mask, [], broken_detection)
except RuntimeError as error:
    assert str(error) == "detector failure"
else:
    raise AssertionError("Detector failure was swallowed")
assert not mask.any()
print("Balloon candidate checks passed: solid/dotted/jagged/dark, scale, empty/open, coverage, masks, coordinates, errors, source preservation")
