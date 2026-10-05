"""Geometry, model disagreements and side effects in repeated-kana recovery."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import cv2
import numpy as np
resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / 'Sources/MangaLadaBallons/Resources'
sys.path.insert(0, str(resources))
from lettering_repetition import recover_repeated_strokes, disputed_repetition


class ModelBoundary:
    def __init__(self, replies=()):
        self.replies, self.calls = iter(replies), []

    def __call__(self, crop):
        self.calls.append(crop.copy())
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        crop[:] = 70  # A model adapter cannot alter the caller's original pixels.
        return reply


image = np.full((60, 240, 3), 245, np.uint8)
mask = np.zeros(image.shape[:2], np.uint8)
for x in (15, 45, 75, 100, 135, 165, 195, 220):
    cv2.rectangle(mask, (x, 12), (x+4, 47), 255, -1)
image[mask > 0] = 10
before, before_mask = image.copy(), mask.copy()
readings = ['パチ'*5, 'パチ'*4, 'ポチ']

# Invalid and unsafe evidence first, with no calls or mutations.
for invalid in (None, np.empty((0, 1, 3), np.uint8), image.astype(float)):
    try:
        recover_repeated_strokes(invalid, readings, [], ModelBoundary())
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid source accepted')
for invalid in (mask.astype(float), mask[:20], np.full_like(mask, 100)):
    try:
        recover_repeated_strokes(image, readings, [invalid], ModelBoundary())
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid external mask accepted')
try:
    recover_repeated_strokes(image, readings, [mask]*4, ModelBoundary())
except ValueError:
    pass
else:
    raise AssertionError('Unbounded mask evidence accepted')
for alternatives in ([], ['パチ'*4]*3, ['コン'*4, 'パチ'*4], ['パチパチ!', 'パチ'*3+'!'],
                     ['ピンポーン', 'ピンポン'], ['ーーー', 'ーーーー'], ['A'*4, 'A'*5],
                     ['パ○'*3, 'パ○'*4], ['', 'パチ'*4, 'パチ'*5]):
    reader = ModelBoundary()
    assert disputed_repetition(alternatives) is None
    assert recover_repeated_strokes(image, alternatives, [mask], reader) is None and not reader.calls
for bad_mask in (np.zeros_like(mask), np.full_like(mask, 255)):
    reader = ModelBoundary()
    assert recover_repeated_strokes(image, readings, [bad_mask], reader) is None and not reader.calls

# A connected stroke crossing the proposed cut prevents a guess.
connected = mask.copy(); connected[29:32, :] = 255
connected_image = image.copy(); connected_image[connected > 0] = 10
reader = ModelBoundary()
assert recover_repeated_strokes(connected_image, readings, [connected], reader) is None and not reader.calls
square = np.pad(image, ((90, 90), (0, 0), (0, 0)), constant_values=245)
square_mask = np.pad(mask, ((90, 90), (0, 0)))
reader = ModelBoundary()
assert recover_repeated_strokes(square, readings, [square_mask], reader) is None and not reader.calls

for replies in (['ポチ'], ['パチパチ', 'パチ'], ['パチパチ', 'パチパチ', 'パチ', 'パチ']):
    reader = ModelBoundary(replies)
    assert recover_repeated_strokes(image, readings, [mask], reader) is None, 'Uncorroborated/unobserved count accepted'
reader = ModelBoundary(['パチパチ', 'パチパチ', 'パチ', 'パチ'])
assert recover_repeated_strokes(image, ['パチ'*4, 'パチ'*3], [mask], reader) is None, 'Unequal count/pixel density accepted'
reader = ModelBoundary(['パチパチ']*4)
observed = recover_repeated_strokes(image, ['パチ'*5, 'プチュ'+'パチ'*3], [mask], reader)
assert observed is not None and observed[0] == 'パチ'*4, 'Corroborated partial sources could not resolve a one-count error'
try:
    recover_repeated_strokes(image, readings, [mask], ModelBoundary([RuntimeError('OCR failed')]))
except RuntimeError as error:
    assert str(error) == 'OCR failed'
else:
    raise AssertionError('OCR error was swallowed')

# Horizontal, vertical, white ink and scaled variants retain exact source counts.
for vertical, inverted, scale in [(False, False, 1), (True, False, 1), (False, True, 1), (False, False, 2)]:
    source, strokes = image.copy(), mask.copy()
    if vertical:
        source, strokes = np.rot90(source).copy(), np.rot90(strokes).copy()
    if inverted:
        source = 255-source
    if scale != 1:
        source = cv2.resize(source, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
        strokes = cv2.resize(strokes, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
    source_before, strokes_before = source.copy(), strokes.copy()
    reader = ModelBoundary(['パチパチ']*4)
    result = recover_repeated_strokes(source, readings, [strokes], reader)
    assert result is not None and result[0] == 'パチ'*4 and len(reader.calls) == 4
    assert np.all(result[1][strokes > 0] == 255) and not np.any(result[1][:5])
    assert np.array_equal(source, source_before) and np.array_equal(strokes, strokes_before)

reader = ModelBoundary(['ポチ']*2)
assert recover_repeated_strokes(image, readings, [mask]*3, reader) is None and len(reader.calls) == 2
assert np.array_equal(image, before) and np.array_equal(mask, before_mask)
print('Repeated lettering checks passed: count evidence, geometry, polarity, bounds, failures and source/mask preservation')
