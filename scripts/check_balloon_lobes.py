"""Contour/column behavior at the detector boundary, including preservation and ambiguous cuts."""
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"))
import cv2
import numpy as np
from balloon_lobes import detect_lobes, retain_cached_regions, split_contour


@dataclass
class Detection:
    xyxy: list[int]
    lines: list
    _detected_font_size: float = 18
    src_is_vertical: bool = True


def column(x, y, width, height):
    return [[x, y], [x + width, y], [x + width, y + height], [x, y + height]]


mask = np.zeros((300, 250), np.uint8)
cv2.ellipse(mask, (90, 170), (65, 100), 0, 0, 360, 255, -1)
cv2.ellipse(mask, (165, 100), (28, 55), 0, 0, 360, 255, -1)
lines = np.array([column(158, 65, 14, 65), column(100, 125, 15, 115), column(65, 125, 15, 100)])
before = mask.copy()
parts = split_contour(mask, lines, 18)
assert len(parts) == 2 and sorted(len(indices) for _, indices in parts) == [1, 2], "Small right lobe remained joined to long left dialogue"
assert all(not np.any(a & b) for i, (a, _) in enumerate(parts) for b, _ in parts[i+1:])
assert np.array_equal(mask, before), "Lobe detection changed the input mask"
plain = np.zeros_like(mask)
cv2.ellipse(plain, (125, 155), (95, 120), 0, 0, 360, 255, -1)
assert not split_contour(plain, lines, 18), "Ordinary parallel columns became separate balloons"
assert not split_contour(mask, np.array([column(90, 70, 95, 160)]), 18)
assert not split_contour(mask, np.empty((0, 4, 2)), 18)
assert not split_contour(np.zeros_like(mask), lines, 18)
crossing = np.array([column(125, 80, 50, 150), column(65, 125, 15, 100)])
assert not split_contour(mask, crossing, 18), "Partition cut through a source column"

# Exercise the same source-color, dilated erase-mask and detector-data path as the app.
image = np.full((800, 800, 3), 145, np.uint8)
image[100:400, 100:350][mask > 0] = (241, 238, 224)
offset_lines = lines + [100, 100]
ink = np.zeros(image.shape[:2], np.uint8)
for line in offset_lines:
    cv2.fillPoly(ink, [line], 255)
    center = line.mean(axis=0).astype(int)
    cv2.line(image, tuple(center - [0, 18]), tuple(center + [0, 18]), (0, 0, 0), 2)
block = Detection([165, 165, 272, 340], offset_lines.tolist())
original, mask_before, saved = image.copy(), ink.copy(), deepcopy(block)
result = detect_lobes(image, ink, [block])
assert len(result.blocks) == 2 and len(result.shapes) == 2
assert sorted(len(b.lines) for b in result.blocks) == [1, 2]
assert result.replaced == {tuple(block.xyxy)}
assert block == saved and np.array_equal(image, original) and np.array_equal(ink, mask_before)
old = dict(id="prior", box=dict(x=165/800, y=165/800, width=107/800, height=175/800))
assert retain_cached_regions([old], result.replaced, 800, 800) == []
manual = dict(old, userDefinedOriginalText=True)
assert retain_cached_regions([manual], result.replaced, 800, 800) == [manual]
print("Balloon lobe checks passed: unequal connected lobes, full-column partition, ordinary/empty/ambiguous input, old/manual caches, source and mask preservation")
