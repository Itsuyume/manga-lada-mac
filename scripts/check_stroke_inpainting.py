"""Verify local glyph repair outputs, permission boundaries and unresolved masks."""
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from stroke_inpainting import prepare_thin_strokes


class StrokeInpaintingChecks(unittest.TestCase):
    def repair(self, source, mask):
        before = source.copy(), mask.copy()
        result, pending = prepare_thin_strokes(source, mask)
        self.assertTrue(np.array_equal(source, before[0]) and np.array_equal(mask, before[1]))
        self.assertFalse(np.shares_memory(result, source) or np.shares_memory(pending, mask))
        self.assertTrue(np.array_equal(result[mask == 0], source[mask == 0]), "Artwork outside glyph permission changed")
        return result, pending

    def test_thin_text_on_light_dark_and_colour_retains_background_and_nearby_art(self):
        for color, foreground in [((255, 255, 255), 0), ((20, 20, 20), 245), ((195, 220, 235), 0)]:
            source = np.full((100, 240, 3), color, np.uint8)
            ink = np.zeros(source.shape[:2], np.uint8)
            cv2.putText(ink, "TEXT.", (25, 65), cv2.FONT_HERSHEY_SIMPLEX, 1, 255, 1, cv2.LINE_AA)
            source[ink > 0] = foreground
            mask = cv2.dilate((ink > 0).astype(np.uint8) * 255, np.ones((3, 3), np.uint8))
            source[:, 210:213] = 70
            result, pending = self.repair(source, mask)
            self.assertFalse(pending.any(), "Thin glyphs were still sent to LaMa")
            error = np.abs(result[mask > 0].astype(float) - np.array(color))
            self.assertLess(error.max(), 4, "Local repair left visible source glyphs on a uniform background")

    def test_gradient_is_interpolated_without_flattening_untouched_pixels(self):
        paper = np.broadcast_to(np.linspace(100, 230, 240, dtype=np.uint8)[None, :, None], (100, 240, 3)).copy()
        mask = np.zeros(paper.shape[:2], np.uint8)
        mask[20:80, 70:77] = 255
        source = paper.copy(); source[mask > 0] = 0
        result, pending = self.repair(source, mask)
        self.assertFalse(pending.any())
        self.assertLess(np.abs(result[mask > 0].astype(float) - paper[mask > 0]).mean(), 4)

    def test_wide_and_image_edge_holes_remain_for_the_neural_painter(self):
        source = np.full((100, 240, 3), 220, np.uint8)
        mask = np.zeros(source.shape[:2], np.uint8)
        mask[20:70, 20:75] = 255
        mask[0:50, 100:103] = 255
        mask[20:70, 150:153] = 255
        source[mask > 0] = 0
        result, pending = self.repair(source, mask)
        self.assertTrue(np.array_equal(result[:, :130], source[:, :130]))
        self.assertTrue(np.array_equal(pending[:, :130], mask[:, :130]))
        self.assertFalse(pending[:, 140:].any())
        self.assertGreater(result[30, 151, 0], 215)

    def test_pending_wide_glyph_does_not_bleed_into_an_adjacent_thin_stroke(self):
        source = np.full((80, 120, 3), 255, np.uint8)
        mask = np.zeros(source.shape[:2], np.uint8)
        mask[20:60, 20:50] = 255  # wide glyph, left for LaMa
        mask[20:60, 51:55] = 255  # thin stroke one pixel away
        source[mask > 0] = 0
        result, pending = self.repair(source, mask)
        self.assertTrue(np.array_equal(pending[20:60, 20:50], mask[20:60, 20:50]), "The wide glyph lost its LaMa mask")
        self.assertTrue(np.array_equal(result[20:60, 20:50], source[20:60, 20:50]), "Pending ink was repaired locally")
        self.assertFalse(pending[20:60, 51:55].any())
        self.assertGreater(int(result[20:60, 51:55].min()), 245, "Unrepaired neighbouring ink bled into the thin stroke")

    def test_empty_mask_and_invalid_contracts(self):
        source = np.full((40, 60, 3), 240, np.uint8)
        mask = np.zeros(source.shape[:2], np.uint8)
        result, pending = self.repair(source, mask)
        self.assertTrue(np.array_equal(result, source) and not pending.any())
        for image, holes in [(source.astype(float), mask), (source, mask.astype(float)), (source[:, :, 0], mask),
                             (source, mask[:-1]), (source[:0], mask[:0])]:
            with self.assertRaises(ValueError):
                prepare_thin_strokes(image, holes)


if __name__ == "__main__":
    unittest.main()
