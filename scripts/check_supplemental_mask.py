"""Behavior checks for glyph masking. Requires the engine's numpy/OpenCV runtime."""
from pathlib import Path
import importlib.util
import sys
import numpy as np
import cv2

sys.dont_write_bytecode = True

source = Path(__file__).resolve().parent.parent / "Sources/MangaLadaBallons/Resources/erase_supplemental_text.py"
spec = importlib.util.spec_from_file_location("mask_adapter", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
image = np.full((1200, 900, 3), 255, np.uint8)
# Four disconnected glyph bodies and separated dakuten-like marks.
for x in (300, 400, 500, 600):
    image[765:820, x:x + 50] = 0
    image[730:745, x:x + 20] = 0
# Panel border and landscape must stay outside the erase mask.
image[600:604, 40:860] = 0
image[940:944, 60:830] = 0
region = {"x": 0.375, "y": 0.658, "width": 0.3, "height": 0.094}
mask, boxes = module.glyph_mask(image, [region])
ink = (image[:, :, 0] == 0)
text_ink = ink[720:830, 290:660]
assert np.all(mask[720:830, 290:660][text_ink] == 255), "Mask left glyph bodies or detached marks behind"
assert not mask[600:604].any() and not mask[940:944].any(), "Mask erased unrelated panel/art strokes"
assert len(boxes) == 1 and all(value >= 0 for value in boxes[0]), "Mask bounds are invalid"
empty, no_boxes = module.glyph_mask(image, [])
assert not empty.any() and not no_boxes, "Empty regions modified the image"
assert image[730:745, 300:320].min() == 0, "Mask generation modified its input"
bounded_region = {"x": 0.3, "y": 0.59, "width": 0.47, "height": 0.13}
bounded, bounds = module.glyph_mask(image, [bounded_region], bounded=True)
assert np.all(bounded[720:830, 290:660][text_ink] == 255), "Manual mask left enclosed text behind"
left, top, right, bottom = bounds[0]
outside = bounded.copy()
outside[top:bottom, left:right] = 0
assert not outside.any(), "Manual mask expanded outside the user selection"
white_text, _ = module.glyph_mask(255 - image, [bounded_region], bounded=True)
assert np.array_equal(white_text, bounded), "White-on-black caption text uses the wrong mask polarity"
# A two-tone background defeats a global threshold: the white edge and black
# interior of each enclosed glyph must both disappear, without touching art.
outlined = np.full((160, 280, 3), (72, 55, 50), np.uint8)
outlined[:, :130] = (154, 125, 135)
outlined[:, 260:264] = 0
for x in [45, 150]:
    cv2.ellipse(outlined, (x, 75), (17, 27), 0, 0, 360, (245, 245, 245), -1)
    cv2.ellipse(outlined, (x, 75), (13, 23), 0, 0, 360, (20, 20, 20), -1)
baseline = outlined.copy()
outline_mask, _ = module.glyph_mask(outlined, [{"x": .02, "y": .05, "width": .85, "height": .85}], bounded=True)
for x in [45, 150]:
    assert outline_mask[75, x] == 255 and outline_mask[75, x + 16] == 255, "Outlined effect left its fill or rim behind"
assert not outline_mask[:, 260:264].any() and np.array_equal(outlined, baseline), "Outline mask changed source or outside artwork"
assert module.outlined_glyph_mask(np.full((160, 280, 3), 255, np.uint8)) is None, "A blank bright region became an outlined effect"
for bad in [{"x": -0.1, "y": 0, "width": 0.2, "height": 0.1},
            {"x": 0, "y": 0, "width": 0, "height": 0.1},
            {"x": 0, "y": 0, "width": float("nan"), "height": 0.1}]:
    try:
        module.glyph_mask(image, [bad], bounded=True)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid manual selection made an erase mask")
try:
    module.glyph_mask(np.full_like(image, 255), [bounded_region], bounded=True)
except ValueError:
    pass
else:
    raise AssertionError("Blank selected area silently accepted")
print("Supplemental mask checks passed: detached glyphs, underestimated box, art/source preservation, bounded manual selection, white captions, empty/invalid input")
