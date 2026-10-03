"""Checks the real external Ballons mask boundary; models are not loaded.

Run with the installed engine's Python and its source directory as the argument.
"""
import copy
from pathlib import Path
import sys

import numpy as np

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(sys.argv[1]).resolve()))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "Sources/MangaLadaBallons/Resources"))
from ballontranslator.modules.inpaint.base import filter_mask_by_bboxes
from ballontranslator.utils.textblock import TextBlock
from japanese_engine_worker import JapaneseEngine

block = TextBlock(xyxy=[100, 60, 160, 240])
block.set_lines_by_xywh([102, 60, 56, 180])
block._detected_font_size = 60
before = copy.deepcopy(block.to_dict())
mask = np.zeros((300, 400), np.uint8)
mask[80:220, 110:168] = 255  # Character tips extend beyond the detector's line polygon.
mask[80:220, 350:355] = 255  # An unrelated stroke outside the text crop.
unchanged = mask.copy()
old = filter_mask_by_bboxes(mask, [block])
assert not np.all(old[80:220, 110:168]), "Fixture no longer reproduces clipped character tips"
regions = JapaneseEngine.inpainting_blocks([block], 400, 300)
filtered = filter_mask_by_bboxes(mask, regions)
assert np.all(filtered[80:220, 110:168] == 255), "Padded erase polygons still clip detected glyph tips"
assert not filtered[80:220, 350:355].any(), "Erase boundary included unrelated artwork"
assert np.array_equal(mask, unchanged), "Preparing erase regions changed the source mask"
assert block.to_dict() == before, "Preparing erase regions changed the original OCR block"
assert JapaneseEngine.inpainting_blocks([], 400, 300) == [], "Empty detection produced erase regions"
edge = TextBlock(xyxy=[0, 0, 400, 300])
edge.set_lines_by_xywh([0, 0, 400, 300]); edge._detected_font_size = 80
edge_regions = JapaneseEngine.inpainting_blocks([edge], 400, 300)
assert edge_regions[0].xyxy == [0, 0, 400, 300], "Padded erase crop escaped the page boundary"
print("Inpaint contract checks passed: actual external mask filter, clipped glyph tips, unrelated artwork, source mask/OCR preservation, empty input, page bounds")
