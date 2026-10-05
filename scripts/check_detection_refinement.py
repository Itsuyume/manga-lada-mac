"""Detector boundary data checks: actual rectangle/mask behavior, no internal model mocks."""
from dataclasses import dataclass
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"))
import numpy as np
from detection_refinement import refine_detection, missing_detections


@dataclass
class Proposal:
    xyxy: list[int]
    _detected_font_size: float


image = np.full((1000, 1000, 3), 145, np.uint8)
mask = np.zeros((1000, 1000), np.uint8)
detail = mask.copy()
detail[100:200, 500:600] = 255  # Rejected distant artwork must never be erased.
base = Proposal([100, 100, 300, 650], 70)
main = Proposal([210, 100, 295, 520], 80)
aside = Proposal([110, 500, 180, 650], 30)
detail[110:500, 220:285] = 255
detail[510:640, 120:170] = 255
source_before, mask_before, detail_before = image.copy(), mask.copy(), detail.copy()
combined, blocks = refine_detection(image, mask, [base], detail, [main, aside, Proposal([500, 100, 600, 200], 30)])
assert blocks == [main, aside], "A main line and small aside were not separated"
assert combined[200, 230] == 255 and combined[550, 140] == 255
assert not combined[100:200, 500:600].any(), "Rejected detail proposal changed the erase mask"
_, stable = refine_detection(image, mask, [base], detail, [main, Proposal(aside.xyxy, 70)])
assert stable == [base], "Ordinary same-size columns were split into unrelated dialogue"
old = Proposal([250, 640, 282, 798], 27)
short = Proposal([314, 643, 344, 694], 29)
_, joined = refine_detection(image, mask, [old], detail, [old, short])
assert joined == [old, short], "A short adjacent lobe was lost or its existing neighbor duplicated"
prior = [{"id": "stable", "box": dict(x=.25, y=.64, width=.032, height=.158), "originalText": "unchanged"}]
assert missing_detections([old, short], prior, 1000, 1000) == [short]
manual = [dict(prior[0], userDefinedBounds=dict(x=.24, y=.63, width=.12, height=.19))]
assert not missing_detections([old, short], manual, 1000, 1000), "A manual region acquired duplicate detections"
assert prior[0]["originalText"] == "unchanged" and prior[0]["id"] == "stable"
empty, regions = refine_detection(image, mask, [], detail, [])
assert not regions and np.array_equal(empty, mask)
for bad in [Proposal([-1, 0, 5, 5], 5), Proposal([10, 10, 10, 20], 5)]:
    try:
        refine_detection(image, mask, [bad], detail, [])
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid detector coordinates were accepted")
assert np.array_equal(image, source_before) and np.array_equal(mask, mask_before) and np.array_equal(detail, detail_before)
print("Detection reconciliation passed: main/aside split, stable columns, short lobe, prior/manual identity, empty/invalid inputs, mask and source preservation")
