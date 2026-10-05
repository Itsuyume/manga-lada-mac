"""Output, geometry and corruption checks; the external model is tested separately."""
from pathlib import Path
import sys
import tempfile
import cv2
import numpy as np

sys.dont_write_bytecode = True
resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
from text_strokes import prepare_text_image, text_stroke_core
from text_stroke_assets import CODE_HASHES, verify_text_strokes
from region_ocr import recognize_region, validate_backend

image = np.full((60, 180, 3), (20, 40, 200), np.uint8)
before = image.copy()
for native, size in [(True, (180, 60)), (False, (1024, 341))]:
    canvas, actual = prepare_text_image(image, native=native)
    assert actual == size and canvas.shape == (1024, 1024, 3)
    assert np.array_equal(canvas[0, 0], (200, 40, 20)), 'BGR/RGB swap lost source color'
    assert np.all(canvas[size[1]:] == 128), 'Model padding does not match training'
    assert not np.shares_memory(canvas, image)
assert np.array_equal(image, before), 'Preparation changed original pixels'
large = np.zeros((2048, 1024, 3), np.uint8)
assert prepare_text_image(large, native=True)[1] == (512, 1024), 'Large input escaped fixed inference budget'

for invalid in [np.zeros((0, 3, 3), np.uint8), np.zeros((10, 10), np.uint8), np.zeros((3, 3, 3), float)]:
    try:
        prepare_text_image(invalid, native=False)
        raise AssertionError('Invalid image accepted')
    except ValueError:
        pass

source = np.full((60, 180, 3), 255, np.uint8)
source[20:40, 40:100] = 0
source[20:40, 140:150] = 0  # Unselected nearby illustration.
mask = np.zeros(source.shape[:2], np.uint8)
mask[19:41, 39:101] = 255
original, mask_before = source.copy(), mask.copy()
core = text_stroke_core(source, mask)
assert np.count_nonzero(core) == 1200 and core[20:40, 40:100].all()
assert not core[:, 140:].any(), 'Model evidence recruited nearby artwork'
assert np.array_equal(text_stroke_core(255-source, mask), core), 'White lettering changed coordinates'
assert not text_stroke_core(source, np.full_like(mask, 255)).any(), 'Whole-background mask was approved'
assert not text_stroke_core(source, np.zeros_like(mask)).any()
assert np.array_equal(source, original) and np.array_equal(mask, mask_before)
for invalid in [mask.astype(float), mask[:10], np.ones_like(mask)]:
    try:
        text_stroke_core(source, invalid)
        raise AssertionError('Invalid model mask accepted')
    except ValueError:
        pass

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    first = next(iter(CODE_HASHES))
    bad = root/first
    bad.parent.mkdir(parents=True)
    bad.write_text('unexpected code')
    try:
        verify_text_strokes(root)
        raise AssertionError('Unverified external code accepted')
    except ValueError:
        pass
    assert bad.read_text() == 'unexpected code', 'Verifier modified external code'

assert validate_backend('hayai-text-strokes') == 'hayai-text-strokes'
held = recognize_region(source, lambda _: 'abc', 'hayai-text-strokes')
assert held['recognitionAlternatives'] == ['abc'], 'Precise masking bypassed OCR disagreement policy'
print('Text strokes passed: bounded geometry, color/polarity, original/artwork preservation, corruption, invalid/blank inputs and OCR hold')
