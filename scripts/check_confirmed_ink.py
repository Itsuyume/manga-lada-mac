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
