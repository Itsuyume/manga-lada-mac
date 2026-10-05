"""Behaviour checks for the detector/OCR boundary, including erase side effects."""
from pathlib import Path
from copy import deepcopy
import sys
sys.dont_write_bytecode = True
import cv2
import numpy as np

resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
from lettering_recovery import recover_lettering
from text_detection import TextDetection


def fixture(background=(239, 222, 245), ink=(15, 15, 15), dotted=False):
    page = np.full((540, 520, 3), 170, np.uint8)
    polygon = np.array([[90, 95], [220, 110], [355, 85], [335, 230], [370, 385], [215, 370], [80, 395], [100, 240]])
    border = np.zeros(page.shape[:2], np.uint8)
    cv2.fillPoly(page, [polygon], background)
    if dotted:
        for a, b in zip(polygon, np.roll(polygon, -1, axis=0)):
            for t in np.arange(0, 1, .06):
                point = np.rint(a+(b-a)*t).astype(int)
                cv2.circle(page, tuple(point), 2, ink, -1)
                cv2.circle(border, tuple(point), 2, 255, -1)
    else:
        cv2.polylines(page, [polygon], True, ink, 3)
        cv2.polylines(border, [polygon], True, 255, 3)
    cv2.putText(page, 'BAM', (125, 235), cv2.FONT_HERSHEY_DUPLEX, 2.3, ink, 4, cv2.LINE_AA)
    proposal = TextDetection((120, 170, 300, 245), .9, "effect")
    return page, border, proposal


class ModelBoundary:
    def __init__(self, proposals, readings=("テスト", "テスト")):
        self.proposals, self.readings, self.calls = proposals, iter(readings), 0

    def detect(self, _):
        return self.proposals

    def read(self, _):
        self.calls += 1
        return next(self.readings)


page, border, proposal = fixture()
original = page.copy()
boundary = ModelBoundary([proposal])
mask, extras = recover_lettering(page, [], boundary.detect, boundary.read)
assert len(extras) == 1 and extras[0]['originalText'] == 'テスト'
assert extras[0]['confidence'] == 0 and 'textKind' not in extras[0], 'Detector hint became a semantic label/probability'
assert np.count_nonzero(mask) > 200 and not np.any(mask[border > 0]), 'Recovery lost glyphs or erased the balloon'
assert np.array_equal(page, original), 'Recovery changed source pixels'
assert not np.any(mask[:130]) and not np.any(mask[290:]), 'Erase mask escaped its verified lettering'

for background, ink, dotted in [((239, 222, 245), (15, 15, 15), True), ((35, 35, 35), (245, 245, 245), False)]:
    variant, outline, candidate = fixture(background, ink, dotted)
    reader = ModelBoundary([candidate])
    confirmed, found = recover_lettering(variant, [], reader.detect, reader.read)
    assert len(found) == 1 and confirmed.any(), 'Dotted or dark balloon was missed'
    assert not np.any(confirmed[outline > 0]), 'Source outline was included in the erase mask'

for existing in [extras, [dict(extras[0], keepsOriginal=True)], [dict(extras[0], userDefinedBounds=extras[0]['box'])]]:
    reader = ModelBoundary([proposal], ())
    empty, found = recover_lettering(page, existing, reader.detect, reader.read)
    assert not empty.any() and not found and reader.calls == 0, 'Existing review was reread or erased'

# Rebuilding an obsolete clean image must also restore previously recovered ink.
# It must not create duplicate regions or rewrite any stored review metadata.
stored = [dict(extras[0], translatedText='보관한 번역', lettering={'fontScale': 1.1})]
stored_before = deepcopy(stored)
reader = ModelBoundary([proposal])
refreshed, found = recover_lettering(page, stored, reader.detect, reader.read, refresh_existing=True)
assert np.array_equal(refreshed, mask) and not found, 'Cached lettering lost its erase mask during regeneration'
assert stored == stored_before and np.array_equal(page, original), 'Mask refresh rewrote source or review data'
for changes in [dict(keepsOriginal=True), dict(userDefinedBounds=extras[0]['box']),
                dict(userDefinedOriginalText=True), dict(userDefinedTextKind=True),
                dict(recognitionAlternatives=['テスト', 'テステ']), dict(balloonShape={'bounds': extras[0]['box']})]:
    reader = ModelBoundary([proposal], ())
    empty, found = recover_lettering(page, [dict(stored[0], **changes)], reader.detect, reader.read, refresh_existing=True)
    assert not empty.any() and not found and reader.calls == 0, 'Mask refresh touched protected or unresolved review'
reader = ModelBoundary([proposal], ())
empty, found = recover_lettering(page, stored + stored, reader.detect, reader.read, refresh_existing=True)
assert not empty.any() and not found and reader.calls == 0, 'Ambiguous region ownership authorized erasure'
reader = ModelBoundary([proposal])
empty, found = recover_lettering(page, [dict(stored[0], originalText='別の文字')], reader.detect, reader.read, refresh_existing=True)
assert not empty.any() and not found, 'New reading disagreed with cached source but still erased it'

for proposals, limit in [([], 8), ([proposal], 0), ([TextDetection(proposal.bounds, .1, 'effect')], 8)]:
    reader = ModelBoundary(proposals, ())
    empty, found = recover_lettering(page, [], reader.detect, reader.read, limit=limit)
    assert not empty.any() and not found and reader.calls == 0

pair = np.concatenate([page, page], axis=1)
second = TextDetection(tuple(v+520 if i%2 == 0 else v for i,v in enumerate(proposal.bounds)), .9, 'text')
reader = ModelBoundary([proposal, second], ('テスト',)*4)
limited_mask, limited = recover_lettering(pair, [], reader.detect, reader.read, limit=1)
assert len(limited) == 1 and reader.calls == 2 and not limited_mask[:, 520:].any(), 'Budget spilled into another balloon'
reader = ModelBoundary([TextDetection((510, 10, 530, 40), .9, 'text')], ())
try:
    recover_lettering(page, [], reader.detect, reader.read)
    raise AssertionError('Detector coordinates outside the source were accepted')
except ValueError:
    pass

clipped = TextDetection((120, 200, 200, 230), .9, 'effect')
reader = ModelBoundary([clipped], ())
clipped_mask, clipped_blocks = recover_lettering(page, [], reader.detect, reader.read)
assert not clipped_mask.any() and not clipped_blocks and reader.calls == 0, 'Part of a connected glyph was erased'

plain = np.full_like(page, 255)
cv2.putText(plain, 'BAM', (125, 235), cv2.FONT_HERSHEY_DUPLEX, 2.3, (0, 0, 0), 4)
reader = ModelBoundary([proposal], ())
empty, found = recover_lettering(plain, [], reader.detect, reader.read)
assert not empty.any() and not found and reader.calls == 0, 'An unenclosed rectangle authorized erasure'

reader = ModelBoundary([proposal], ('テスト', 'テストト', 'テステ'))
_, uncertain = recover_lettering(page, [], reader.detect, reader.read)
assert uncertain[0]['recognitionAlternatives'] == ['テスト', 'テストト', 'テステ']

for invalid in [np.empty((0, 0, 3), np.uint8), page.astype(float)]:
    try:
        recover_lettering(invalid, [], lambda _: [], lambda _: '')
        raise AssertionError('Invalid image accepted')
    except ValueError:
        pass
for limit in [-1, 9, 1.5, True]:
    try:
        recover_lettering(page, [], lambda _: [], lambda _: '', limit=limit)
        raise AssertionError('Invalid recovery budget accepted')
    except ValueError:
        pass

def failed(_):
    raise RuntimeError('external model failure')

for detect, read in [(failed, failed), (lambda _: [proposal], failed)]:
    try:
        recover_lettering(page, [], detect, read)
        raise AssertionError('Model error was swallowed')
    except RuntimeError as error:
        assert str(error) == 'external model failure'
assert np.array_equal(page, original)
print('Lettering recovery passed: bounded ink, original outlines, review exclusion, OCR uncertainty, empty/boundary/error paths')
