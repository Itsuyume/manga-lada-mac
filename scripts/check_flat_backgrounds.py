"""Pixel-level cleanup checks; unresolved regions still require real inpainting."""
from pathlib import Path
import sys

import numpy as np

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
from flat_background import prepare_flat_backgrounds


def prepare(source, mask, boxes, base=None):
    base = source if base is None else base
    evidence = source.copy(), base.copy(), mask.copy()
    try:
        result, pending = prepare_flat_backgrounds(source, base, mask, boxes)
    finally:
        assert all(np.array_equal(a, b) for a, b in zip(evidence, (source, base, mask))), "Cleanup modified input evidence"
    assert not np.shares_memory(result, base) and not np.shares_memory(pending, mask), "Returned buffers alias caller inputs"
    assert np.array_equal(result[mask == 0], base[mask == 0]), "Cleanup changed unmasked artwork"
    return result, pending


def run():
    bounds = [[25, 20, 75, 80]]
    mask = np.zeros((100, 160), np.uint8)
    mask[30:70, 40:60] = 255
    for color in [(240, 240, 240), (16, 16, 16), (190, 220, 235)]:
        source = np.full((100, 160, 3), color, np.uint8)
        source[30:70, 40:60] = 120
        result, pending = prepare(source, mask, bounds)
        assert np.all(result[mask > 0] == color), "Solid backdrop retained the original ink"
        assert not pending.any(), "Resolved ink was still sent to the neural model"
        base = source.copy(); base[0:10] = 31
        result, _ = prepare(source, mask, bounds, base)
        assert np.all(result[:10] == 31), "Earlier cleanup was replaced with the original image"
        once, _ = prepare(source, mask, bounds)
        twice, _ = prepare(source, mask, bounds + bounds)
        assert np.array_equal(once, twice), "Duplicate bounds changed the result"
    check_unresolved(source, mask, bounds)
    check_mixed_regions()
    check_nearby_artwork()
    check_separate_strokes_near_a_frame()
    check_invalid_inputs(source, mask)
    print("Flat background checks passed: white/dark/pastel cleanup, neural-mask exclusion, artwork/evidence/base preservation, empty/mixed/duplicate/invalid regions, gradients/textures/insufficient evidence remain pending")


def check_unresolved(source, mask, bounds):
    textured = source.copy(); textured[30:70, 37:40] = 90
    gradient = np.broadcast_to(np.arange(160, dtype=np.uint8)[None, :, None], (100, 160, 3)).copy()
    for image, ink, boxes in [(textured, mask, bounds), (gradient, mask, bounds),
                              (source, np.full_like(mask, 255), bounds), (source, mask, []),
                              (source, np.zeros_like(mask), bounds)]:
        result, pending = prepare(image, ink, boxes)
        assert np.array_equal(result, image), "Unverified background was flattened"
        assert np.array_equal(pending, ink), "Unresolved strokes were removed from the neural mask"


def check_mixed_regions():
    source = np.full((100, 160, 3), 240, np.uint8)
    source[:, 80:] = np.arange(80, 160, dtype=np.uint8)[None, :, None]
    mask = np.zeros((100, 160), np.uint8)
    mask[30:70, 40:60] = 255; mask[30:70, 110:130] = 255
    source[mask > 0] = 0
    result, pending = prepare(source, mask, [[25, 20, 75, 80], [95, 20, 145, 80]])
    assert np.all(result[30:70, 40:60] == 240) and not pending[:, :80].any(), "Solid caption remained pending"
    assert np.array_equal(result[:, 80:], source[:, 80:]), "Textured neighboring region was changed"
    assert np.array_equal(pending[:, 80:], mask[:, 80:]), "Textured ink no longer reaches LaMa"


def check_nearby_artwork():
    source = np.full((100, 160, 3), (190, 220, 235), np.uint8)
    mask = np.zeros((100, 160), np.uint8)
    mask[30:70, 40:60] = 255
    source[mask > 0] = 0
    source[20:24, 68:75] = 31  # Balloon edge in the padded crop, away from all ink.
    result, pending = prepare(source, mask, [[25, 20, 75, 80]])
    assert not pending.any(), "Distant balloon edge prevented measured solid-background cleanup"
    assert np.all(result[mask > 0] == (190, 220, 235)), "Flat pastel ink retained neural residue"
    assert np.array_equal(result[mask == 0], source[mask == 0]), "Nearby artwork was changed"
    source[30:70, 37:40] = 31  # The edge now touches the ink evidence.
    result, pending = prepare(source, mask, [[25, 20, 75, 80]])
    assert np.array_equal(pending, mask), "Ink touching mixed colors was incorrectly flattened"
    assert np.array_equal(result, source), "Unverified local backdrop was modified"
    source = np.full((160, 200, 3), 16, np.uint8)
    mask = np.zeros((160, 200), np.uint8)
    mask[30:130, 30:170] = 255
    source[mask > 0] = 230
    result, pending = prepare(source, mask, [[15, 15, 185, 145]])
    assert not pending.any() and np.all(result == 16), "Wide strokes discarded sufficient uniform outer evidence"


def check_invalid_inputs(source, mask):
    bad_boxes = [[-1, 0, 20, 20], [0, 0, 161, 20], [0, 0, 20, 101], [2, 2, 2, 3],
                 [0, 0, 1.5, 20], [0, 0, float("nan"), 20]]
    for box in bad_boxes:
        try:
            prepare(source, mask, [[25, 20, 75, 80], box])
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid region was accepted")
    for image, ink in [(source[:, :, 0], mask), (source.astype(np.float32), mask),
                       (source, mask.astype(np.float32)), (source, mask[:50])]:
        try:
            prepare(image, ink, [])
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid image/mask contract was accepted")


def check_separate_strokes_near_a_frame():
    source = np.full((100, 160, 3), 255, np.uint8)
    mask = np.zeros((100, 160), np.uint8)
    mask[30:60, 30:42] = mask[30:60, 95:107] = 255
    source[mask > 0] = 0
    source[15:85, 65:68] = 0
    result, pending = prepare(source, mask, [[20, 15, 120, 80]])
    assert not pending.any(), "A frame between separate glyphs forced all ink through LaMa"
    assert np.all(result[mask > 0] == 255), "Confirmed separate glyphs left neural residue"
    assert np.array_equal(result[:, 65:68], source[:, 65:68]), "Component cleanup erased the frame"
    source[30:60, 92:95] = 100
    result, pending = prepare(source, mask, [[20, 15, 120, 80]])
    assert not pending[:, :60].any() and np.array_equal(pending[:, 90:], mask[:, 90:])
    assert np.array_equal(result[:, 90:], source[:, 90:]), "A nearby mixed colour was flattened"


if __name__ == "__main__":
    run()
