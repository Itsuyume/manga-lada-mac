"""Incomplete glyph masks must recover observed strokes, not balloon/art pixels."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from erase_supplemental_text import complete_confirmed_glyph_mask, glyph_mask
from text_ink import foreground_mask


class ConfirmedInkChecks(unittest.TestCase):
    def test_partial_and_antialiased_strokes_on_light_dark_and_colour(self):
        for background, foreground in [(255, 0), (30, 245), (210, 0)]:
            for scale in (1, 2):
                source = np.full((90 * scale, 340 * scale, 3), background, np.uint8)
                alpha = np.zeros(source.shape[:2], np.uint8)
                cv2.putText(alpha, "EDGE.", (25 * scale, 65 * scale), cv2.FONT_HERSHEY_SIMPLEX,
                            1.5 * scale, 255, 3 * scale, cv2.LINE_AA)
                for channel in range(3):
                    source[:, :, channel] = (background + (foreground - background) * alpha.astype(float) / 255).astype(np.uint8)
                seed = cv2.erode((alpha > 180).astype(np.uint8) * 255, np.ones((3, 3), np.uint8))
                # A nearby panel line and disconnected unrecognized mark are negative evidence.
                source[:, 310 * scale:313 * scale] = foreground
                source[12 * scale:16 * scale, 230 * scale:235 * scale] = foreground
                before = deepcopy(source), seed.copy()
                completed = complete_confirmed_glyph_mask(source, seed)
                self.assertTrue(np.all(completed[alpha >= 24] == 255), "Observed glyph edge remained")
                self.assertFalse(completed[:, 310 * scale:313 * scale].any(), "Panel edge became text")
                self.assertFalse(completed[12 * scale:16 * scale, 230 * scale:235 * scale].any(), "Unrecognized punctuation became text")
                self.assertTrue(np.array_equal(before[0], source) and np.array_equal(before[1], seed))

    def test_empty_and_invalid_evidence(self):
        source = np.full((80, 120, 3), 250, np.uint8)
        seed = np.zeros(source.shape[:2], np.uint8)
        self.assertFalse(complete_confirmed_glyph_mask(source, seed).any())
        for invalid in (seed[:-1], seed.astype(float)):
            with self.assertRaises(ValueError):
                complete_confirmed_glyph_mask(source, invalid)
        self.assertEqual(foreground_mask(np.zeros((0, 5), np.uint8)).shape, (0, 5))
        self.assertFalse(foreground_mask(np.full((10, 10), 125, np.uint8)).any())
        for invalid in (None, np.zeros((2, 2), float), np.zeros((2, 2, 3), np.uint8)):
            with self.assertRaises(ValueError):
                foreground_mask(invalid)
        with self.assertRaises(ValueError):
            foreground_mask(np.full((10, 10), 125, np.uint8), float("nan"))

    def test_bounded_text_uses_relative_contrast_on_mid_tone_paper(self):
        for background, foreground in [((150, 105, 140), 0), ((125, 125, 125), 0),
                                       ((165, 170, 160), 245)]:
            source = np.full((100, 330, 3), background, np.uint8)
            alpha = np.zeros(source.shape[:2], np.uint8)
            cv2.putText(alpha, "EDGE FINE", (15, 65), cv2.FONT_HERSHEY_SIMPLEX,
                        1.2, 255, 3, cv2.LINE_AA)
            for channel, color in enumerate(background):
                source[:, :, channel] = np.round(color + (foreground - color) * alpha.astype(float) / 255).astype(np.uint8)
            source[:, 310:313] = foreground
            before = source.copy()
            mask, _ = glyph_mask(source, [dict(x=0, y=0, width=1, height=1)], bounded=True)
            self.assertTrue(np.all(mask[alpha >= 180] > 0), "Mid-tone paper inverted letters into their counters")
            self.assertFalse(mask[:, 310:313].any(), "Nearby panel edge was erased")
            self.assertTrue(np.array_equal(source, before))

    def test_panel_ink_on_the_perimeter_cannot_reverse_text_polarity(self):
        source = np.full((70, 220, 3), 255, np.uint8)
        source[:3] = source[-3:] = source[:, :3] = 0
        alpha = np.zeros(source.shape[:2], np.uint8)
        cv2.putText(alpha, "FLYING?", (15, 45), cv2.FONT_HERSHEY_SIMPLEX, .85, 255, 2, cv2.LINE_AA)
        source[alpha > 0] = (255 - alpha[alpha > 0])[:, None]
        mask, boxes = glyph_mask(source, [dict(x=0, y=0, width=1, height=1)], bounded=True)
        completed = complete_confirmed_glyph_mask(source, mask)
        self.assertEqual(boxes, [[0, 0, 220, 70]])
        self.assertTrue(np.all(completed[alpha >= 12] > 0), "White-paper text was inverted into background")
        self.assertFalse(completed[:3].any() or completed[-3:].any() or completed[:, :3].any())


if __name__ == "__main__":
    unittest.main()
