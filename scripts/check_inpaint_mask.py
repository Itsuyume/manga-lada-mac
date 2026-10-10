"""Pixel coverage and mutation checks for the restoration boundary."""
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import numpy as np
from inpaint_mask import reconstruction_mask, reconstruction_bounds


class InpaintMaskChecks(unittest.TestCase):
    def test_every_pending_pixel_is_covered_even_beyond_a_reading_rectangle(self):
        mask = np.zeros((120, 100), np.uint8)
        mask[20:90, 40:55] = 255
        mask[22:28, 59:63] = 255  # A separate furigana component.
        mask[:4, :3] = mask[115:, 97:] = 255
        before = mask.copy()
        context = reconstruction_mask(mask)
        covered = np.zeros_like(mask)
        bounds = reconstruction_bounds(context)
        for left, top, right, bottom in bounds:
            self.assertTrue(0 <= left < right <= 100 and 0 <= top < bottom <= 120)
            covered[top:bottom, left:right] = 255
        self.assertTrue(np.all(covered[context > 0] == 255), "A restoration window clipped approved text")
        self.assertTrue(np.all(context[mask > 0] > 0))
        self.assertTrue(np.array_equal(mask, before) and not np.shares_memory(mask, context))

    def test_small_fragments_receive_surrounding_source_context(self):
        mask = np.zeros((400, 500), np.uint8)
        mask[150:155, 200:204] = mask[168:174, 228:232] = 255
        bounds = reconstruction_bounds(mask)
        self.assertEqual(len(bounds), 1, "Adjacent fragments were painted independently")
        left, top, right, bottom = bounds[0]
        self.assertTrue(left <= 136 and top <= 86 and right >= 296 and bottom >= 238)

    def test_empty_and_invalid_input(self):
        mask = np.zeros((30, 40), np.uint8)
        self.assertFalse(reconstruction_mask(mask).any())
        self.assertEqual(reconstruction_bounds(mask), [])
        for bad in (None, mask.astype(float), mask[:, :, None], mask[:0]):
            for function in (reconstruction_mask, reconstruction_bounds):
                with self.assertRaises(ValueError):
                    function(bad)


if __name__ == "__main__":
    unittest.main()
