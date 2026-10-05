"""Behavior at the OCR-model boundary, plus real candidate geometry and side effects."""
from pathlib import Path
import json
import tempfile
import sys
sys.dont_write_bytecode = True
if len(sys.argv) > 2:
    raise ValueError("Usage: check_lettering_ocr.py [packaged-resource-directory]")
resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from lettering_ocr import read_lettering, crop_variants
from balloon_candidates import balloon_candidates
from lettering_regions import inspect_lettering_regions, lettering_crops
from hayai_lettering import verify_installation, MODEL_ID, MODEL_REVISION, VISION_REVISION
from region_ocr import recognize_region, validate_backend


class ModelBoundary:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def __call__(self, image):
        self.calls.append(image.copy())
        result = next(self.replies)
        if isinstance(result, Exception):
            raise result
        return result


# Empty, malformed, failed and disagreeing input before the happy path.
reader = ModelBoundary([])
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    manifest = dict(model=MODEL_ID, revision=MODEL_REVISION, visionRevision=VISION_REVISION,
                    files={"model/modeling_hayai.py": "unverified"})
    path = root/"manifest.json"
    path.write_text(json.dumps(manifest))
    original_manifest = path.read_bytes()
    try:
        verify_installation(root)
    except ValueError:
        pass
    else:
        raise AssertionError("Unpinned model manifest accepted")
    assert list(root.iterdir()) == [path] and path.read_bytes() == original_manifest
assert read_lettering(np.full((30, 40, 3), 255, np.uint8), reader).status == "blank"
assert not reader.calls
for invalid in [None, np.zeros((0, 2, 3), np.uint8), np.zeros((20, 20)), np.zeros((20, 20, 3), np.float32)]:
    try:
        read_lettering(invalid, reader)
    except ValueError:
        pass
    else:
        raise AssertionError("Malformed crop accepted")

crop = np.full((150, 80, 3), (220, 235, 250), np.uint8)
cv2.putText(crop, "E", (10, 130), cv2.FONT_HERSHEY_SIMPLEX, 3.5, (20, 20, 20), 9)
before = crop.copy()
for backend in ("", "automatic", None):
    try:
        validate_backend(backend)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid backend silently selected a model")
pending = recognize_region(crop, ModelBoundary(["パチパチ", "パチパチパチ", "ポチ"]), "hayai")
assert pending["originalText"] == "パチパチ"
assert pending["recognitionAlternatives"] == ["パチパチ", "パチパチパチ", "ポチ"]
assert pending["confidence"] == 0  # Agreement is not a calibrated probability.
accepted = recognize_region(crop, ModelBoundary(["バビュン", "バビュン"]), "hayai")
assert accepted["originalText"] == "バビュン" and "recognitionAlternatives" not in accepted
empty = recognize_region(np.full((30, 40, 3), 255, np.uint8), ModelBoundary([]), "hayai")
assert empty["recognitionAlternatives"] == [] and empty["originalText"] == ""
legacy = recognize_region(crop, ModelBoundary(["原文"]), "manga")
assert legacy["originalText"] == "原文" and "recognitionAlternatives" not in legacy
assert np.array_equal(crop, before)
failed = ModelBoundary([RuntimeError("OCR unavailable")])
try:
    read_lettering(crop, failed)
except RuntimeError as error:
    assert str(error) == "OCR unavailable"
else:
    raise AssertionError("Model failure was swallowed")
assert np.array_equal(crop, before)

disagreement = ModelBoundary(["パチパチパチ", "パチパチ", "ポチ"])
result = read_lettering(crop, disagreement)
assert result.status == "needsReview" and result.text is None
assert result.readings == ("パチパチパチ", "パチパチ", "ポチ")
assert len(disagreement.calls) == 3, "Unbounded model retries"
assert np.array_equal(crop, before)

# Two altered views may share the same wrong kana; they cannot overrule the source.
for source in ("少し黙っていろ", "", "NOT TEXT"):
    changed = ModelBoundary([source, "少し黙っている", "少し黙っている"])
    result = read_lettering(crop, changed)
    assert result.status == "needsReview" and result.text is None, "Altered views overruled the source reading"
    assert result.readings == (source, "少し黙っている", "少し黙っている")
    assert len(changed.calls) == 3 and np.array_equal(crop, before)
for backend in ("hayai", "hayai-detected", "hayai-text-strokes"):
    changed = recognize_region(crop, ModelBoundary(["少し黙っていろ", "少し黙っている", "少し黙っている"]), backend)
    assert changed["originalText"] == "少し黙っていろ"
    assert changed["recognitionAlternatives"] == ["少し黙っていろ", "少し黙っている"]

empty = read_lettering(crop, ModelBoundary(["", "", ""]))
assert empty.text is None and empty.status == "needsReview", "Empty agreement is not recognition"
non_japanese = read_lettering(crop, ModelBoundary(["NOT TEXT", "NOT TEXT", "NOT TEXT"]))
assert non_japanese.text is None
for punctuation in ("・・・", "ーーー", "123"):
    assert read_lettering(crop, ModelBoundary([punctuation]*3)).text is None
stable = ModelBoundary(["パチパチ", "ﾊﾟﾁﾊﾟﾁ"])
result = read_lettering(crop, stable)
assert result.text == "パチパチ" and result.status == "consistent"
assert len(stable.calls) == 2
repeat_mismatch = ModelBoundary(["パチパチパチパチパチ", "パチパチパチパチパチ", "パチパチパチパチ"])
result = read_lettering(crop, repeat_mismatch)
assert result.status == "needsReview" and result.text is None and len(repeat_mismatch.calls) == 3
assert len(result.readings) == 3, "Repeated syllables lost their count-disagreement evidence"
assert read_lettering(crop, ModelBoundary(["コンコンコン"]*3)).text == "コンコンコン"
assert read_lettering(crop, ModelBoundary(["ハハハ", "ハハハハ", "ハハハ"])).status == "needsReview"
recovered = read_lettering(crop, ModelBoundary(["バビュン", "バシュッ", "バビュン"]))
assert recovered.text == "バビュン" and len(recovered.readings) == 3
masked = read_lettering(crop, ModelBoundary(["ピ○チュウ", "ピ○チュウ"]))
assert masked.text == "ピ○チュウ", "Masked text was guessed or expanded"

for white in [False, True]:
    sample = 255-crop if white else crop
    variants = crop_variants(sample)
    assert len(variants) == 3 and all(v.dtype == np.uint8 and v.shape[2] == 3 for v in variants)
    assert variants[1].shape[0] > sample.shape[0]
    assert min(variants[2][0, 0]) == 255
    assert not np.shares_memory(variants[0], sample)

# A large connected glyph is a candidate, never an automatic erase instruction.
page = np.full((600, 600, 3), 170, np.uint8)
angles = np.linspace(0, 2*np.pi, 48, endpoint=False)
radii = np.where(np.arange(48) % 2, .88, 1.)
outline = np.column_stack((240+130*radii*np.cos(angles), 290+240*radii*np.sin(angles))).astype(np.int32)
cv2.fillPoly(page, [outline], (235, 235, 235))
cv2.polylines(page, [outline], True, (10, 10, 10), 2)
cv2.putText(page, "E", (174, 428), cv2.FONT_HERSHEY_SIMPLEX, 8, (15, 15, 15), 25)
original = page.copy()
assert not balloon_candidates(page, []), "Legacy strict detector path changed"
candidates = balloon_candidates(page, [], connected_lettering=True)
assert candidates and any(c.bounds[0] < 180 and c.bounds[2] > 320 for c in candidates)
assert np.array_equal(page, original)
assert not balloon_candidates(page, [(150, 220, 360, 470)], connected_lettering=True)
cv2.fillPoly(page, [outline], (235, 235, 235))
cv2.polylines(page, [outline], True, (10, 10, 10), 2)
assert not balloon_candidates(page, [], connected_lettering=True), "Empty outline became text"

assert inspect_lettering_regions(np.full((100, 100, 3), 255, np.uint8), ModelBoundary([])) == []
cropped = lettering_crops(crop, "crop")
assert cropped[0][0] == (0, 0, crop.shape[1], crop.shape[0])
assert np.array_equal(cropped[0][1], crop) and not np.shares_memory(cropped[0][1], crop)
try:
    lettering_crops(crop, "translate")
except ValueError:
    pass
else:
    raise AssertionError("Unknown mode accepted")
for scale in (.6, 1., 1.8):
    scaled = cv2.resize(original, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    candidates = lettering_crops(scaled, "scan")
    assert candidates and len(candidates) <= 8
    assert np.array_equal(scaled, cv2.resize(original, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA))
print("Lettering OCR checks passed: invalid/blank/error, bounded disagreement, kana and repetition preservation, polarity, connected glyphs, source preservation")
