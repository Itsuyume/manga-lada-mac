"""Behaviour checks at external segmentation/OCR boundaries, no model downloads."""
from pathlib import Path
import sys
import tempfile
import cv2
import numpy as np

sys.dont_write_bytecode = True
resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
from lettering_strokes import confirmed_strokes, stroke_points, verify_stroke_model
from lettering_recovery import recover_lettering
from text_detection import TextDetection


class Recognizer:
    def __init__(self, texts):
        self.texts, self.calls = iter(texts), 0

    def __call__(self, _):
        self.calls += 1
        return next(self.texts)


image = np.full((160, 240, 3), 255, np.uint8)
cv2.putText(image, 'BAM', (35, 100), cv2.FONT_HERSHEY_DUPLEX, 1.6, (0, 0, 0), 6)
source = image.copy()
mask = (cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) < 100).astype(np.uint8)*255
original_mask = mask.copy()
reader = Recognizer(['テスト'])
confirmed = confirmed_strokes(image, 'テスト', [mask], reader)
assert confirmed is not None and np.all(confirmed[mask > 0] == 255)
assert not confirmed[:45].any() and not confirmed[120:].any(), 'Edge completion erased distant artwork'
assert np.array_equal(source,image) and np.array_equal(mask,original_mask), 'Stroke confirmation mutated its inputs'
assert len(stroke_points(image,(20,40,210,120))) <= 4
assert all(mask[y,x] for x,y in stroke_points(image,(20,40,210,120)))
assert not stroke_points(np.full_like(image,255),(0,0,240,160)), 'Blank background generated prompts'

reader = Recognizer([])
assert confirmed_strokes(image,'テスト',[],reader) is None
assert confirmed_strokes(image,'テスト',[np.zeros_like(mask),np.full_like(mask,255)],reader) is None
background = np.zeros_like(mask); background[5:30,10:220] = 255
assert confirmed_strokes(image,'テスト',[background],reader) is None and reader.calls == 0
assert confirmed_strokes(image,'テスト',[mask],Recognizer(['テストト'])) is None, 'Partial/mismatching glyphs were erased'
assert confirmed_strokes(image,'テスト',[mask],Recognizer([''])) is None, 'Empty isolated OCR was accepted'
bad_masks = [mask.astype(float), np.zeros((2,2),np.uint8), np.full_like(mask,127)]
for invalid in bad_masks:
    try:
        confirmed_strokes(image,'テスト',[invalid],Recognizer([]))
        raise AssertionError('Malformed segmentation accepted')
    except ValueError:
        pass
for bounds in [(-1,0,240,160),(0,0,241,160),(0,0,0,160),(0.,0,240,160)]:
    try:
        stroke_points(image,bounds)
        raise AssertionError('Invalid stroke bounds accepted')
    except ValueError:
        pass
for invalid in [np.empty((0,0,3),np.uint8),image.astype(float)]:
    try:
        stroke_points(invalid,(0,0,240,160))
        raise AssertionError('Invalid image accepted')
    except ValueError:
        pass
with tempfile.TemporaryDirectory() as folder:
    file = Path(folder)/'incorrect.onnx'
    file.write_bytes(b'not a model')
    try:
        verify_stroke_model(file)
        raise AssertionError('Corrupt weights accepted')
    except ValueError:
        pass
    assert file.read_bytes() == b'not a model'


def failed(*_):
    raise RuntimeError('external model failure')


try:
    confirmed_strokes(image,'テスト',[mask],failed)
    raise AssertionError('OCR failure was swallowed')
except RuntimeError as error:
    assert str(error) == 'external model failure'

# Production recovery: use the original crop for OCR, then corroborate with isolated strokes.
proposal = TextDetection((30,60,160,110),.9,'effect')
calls = []
def segment(crop,bounds):
    calls.append(bounds)
    return [(cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY) < 100).astype(np.uint8)*255]

recovered, blocks = recover_lettering(image,[],lambda _: [proposal],Recognizer(['テスト']*3),segment=segment)
assert len(blocks) == 1 and recovered.any() and len(calls) == 1
assert blocks[0]['originalText'] == 'テスト' and 'textKind' not in blocks[0], 'Detector class became a semantic label'
assert not recovered[:45].any() and not recovered[130:].any()
calls.clear()
empty, uncertain = recover_lettering(image,[],lambda _: [proposal],Recognizer(['テスト','テストト','テス']),segment=segment)
assert not uncertain and not empty.any() and not calls, 'Uncertain source invoked erasure model'
empty, excluded = recover_lettering(image,blocks,lambda _: [proposal],Recognizer([]),segment=failed)
assert not excluded and not empty.any(), 'Existing review was altered'

# Rejected candidates also consume the per-page budget; model calls cannot grow without bound.
wide = np.tile(image,(1,3,1))
proposals = [TextDetection(tuple(v+240*n if i%2 == 0 else v for i,v in enumerate(proposal.bounds)),.9,'effect') for n in range(3)]
reader = Recognizer(['テスト']*2)
empty, rejected = recover_lettering(wide,[],lambda _: proposals,reader,limit=1,segment=lambda *_: [])
assert not rejected and not empty.any() and reader.calls == 2, 'Rejected candidates bypassed the OCR budget'
try:
    recover_lettering(image,[],lambda _: [proposal],Recognizer(['テスト']*2),segment=failed)
    raise AssertionError('Segmentation failure was swallowed')
except RuntimeError as error:
    assert str(error) == 'external model failure'
assert np.array_equal(image,source) and np.array_equal(mask,original_mask)
print('Lettering strokes passed: source confirmation, bounded ink, negative masks, budget, review exclusion, errors and original preservation')
