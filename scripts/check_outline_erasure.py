"""Pixel regressions for automatic glyph-rim completion, without loading AI models."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import sys
import unittest

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from japanese_engine_worker import JapaneseEngine
from erase_supplemental_text import outlined_glyph_mask
from balloon_geometry import BalloonGeometry
from balloon_erase_mask import protect_balloon_outlines


def block(bounds, size):
    # Data at the external CTD boundary; production masking itself is not mocked.
    return SimpleNamespace(xyxy=bounds, _detected_font_size=size)


class OutlineErasureChecks(unittest.TestCase):
    def complete(self, source, mask, blocks):
        before = source.copy(), mask.copy(), deepcopy(blocks)
        result = JapaneseEngine.expand_outline_mask(source, mask, blocks)
        self.assertTrue(np.array_equal(before[0], source), "Source pixels mutated")
        self.assertTrue(np.array_equal(before[1], mask), "Detector evidence mutated")
        self.assertEqual(blocks, before[2], "OCR bounds changed during erasure")
        self.assertFalse(np.shares_memory(mask, result))
        self.assertTrue(np.all(result[mask > 0] == mask[mask > 0]), "Confirmed ink lost")
        return result

    def test_large_plain_lettering_preserves_jagged_outline(self):
        for scale in (.5, 1, 2):
            source, mask, border = jagged_fixture(scale)
            bounds = [int(value * scale) for value in (125, 140, 245, 420)]
            result = self.complete(source, mask, [block(bounds, 100 * scale)])
            self.assertFalse(result[border > 0].any(), "A large font erased the jagged balloon")
            self.assertTrue(np.array_equal(result, mask), "Unoutlined text expanded across coloured paper")

    def test_dark_white_and_pastel_backgrounds_do_not_authorize_expansion(self):
        for background, foreground in [(25, 240), (255, 0), (185, 0)]:
            source = np.full((220, 300, 3), background, np.uint8)
            mask = np.zeros(source.shape[:2], np.uint8)
            cv2.putText(mask, "HI", (60, 150), cv2.FONT_HERSHEY_SIMPLEX, 3, 255, 7)
            source[mask > 0] = foreground
            result = self.complete(source, mask, [block([50, 60, 200, 170], 140)])
            self.assertTrue(np.array_equal(result, mask))

    def test_only_observed_rims_complete_the_mask(self):
        source, mask = outlined_fixture()
        result = self.complete(source, mask, [block([35, 42, 181, 118], 60)])
        for x in (60, 155):
            self.assertEqual(result[80, x + 22], 255, "Confirmed white rim remained")
        self.assertFalse(result[:, 205:].any(), "Unrecognized neighbouring glyph was erased")
        self.assertFalse(result[20:33, 95:117].any(), "Unfilled bright decoration became an outline")
        core = outlined_glyph_mask(source, mask)
        allowed = cv2.dilate(core, np.ones((3, 3), np.uint8)) | mask
        self.assertTrue(np.array_equal(result, allowed), "Font-size dilation escaped observed rims")

    def test_overlapping_boxes_cannot_compound_dilation(self):
        source, mask = outlined_fixture()
        first = block([35, 42, 181, 118], 60)
        second = block([25, 35, 190, 125], 95)
        once = self.complete(source, mask, [first])
        repeated = self.complete(source, mask, [first, first])
        forwards = self.complete(source, mask, [first, second])
        backwards = self.complete(source, mask, [second, first])
        self.assertTrue(np.array_equal(once, repeated))
        self.assertTrue(np.array_equal(forwards, backwards))

    def test_empty_or_unconfirmed_outline_preserves_evidence(self):
        source, mask = outlined_fixture()
        self.assertTrue(np.array_equal(self.complete(source, mask, []), mask))
        self.assertFalse(self.complete(source, np.zeros_like(mask), [block([20, 20, 195, 145], 60)]).any())
        self.assertIsNone(outlined_glyph_mask(np.full_like(source, 240)))
        self.assertIsNone(outlined_glyph_mask(source[:, :115], mask[:, :115]), "One ambiguous ring became glyph evidence")

    def test_invalid_mask_bounds_and_font_size_raise(self):
        source, mask = outlined_fixture()
        for bad in [block([-1, 0, 100, 100], 20), block([0, 0, 0, 100], 20),
                    block([0, 0, 400, 100], 20), block([0, 0, 100, 100], float("nan")),
                    block([0, 0, 100, 100], 0)]:
            with self.assertRaises(ValueError):
                self.complete(source, mask, [bad])
        for bad_mask in (mask[:-1], mask.astype(np.float32)):
            with self.assertRaises(ValueError):
                JapaneseEngine.expand_outline_mask(source, bad_mask, [])
            with self.assertRaises(ValueError):
                outlined_glyph_mask(source, bad_mask)

    def test_detector_border_contamination_is_removed_before_painting(self):
        for scale in (.5, 1, 2):
            source, ink, border = jagged_fixture(scale)
            # The source contour is measured before optional rim completion.
            geometry = BalloonGeometry(source, text_mask=ink)
            contaminated = ink | border
            region = dict(box=dict(x=125/700, y=140/700, width=120/700, height=280/700),
                          detectedFontSize=100*scale)
            before = contaminated.copy(), source.copy()
            protected = protect_balloon_outlines(contaminated, [region], geometry)
            self.assertFalse(protected[border > 0].any(), "Detector-labelled border reached the painter")
            self.assertTrue(np.all(protected[ink > 0] == ink[ink > 0]), "Boundary protection clipped lettering")
            self.assertTrue(np.array_equal(before[0], contaminated) and np.array_equal(before[1], source))
            self.assertFalse(np.any(protected > contaminated), "Protection granted new erase permission")
            repeated = protect_balloon_outlines(protected, [region, region], geometry)
            self.assertTrue(np.array_equal(protected, repeated))

    def test_no_enclosure_or_regions_never_invent_a_border(self):
        source, ink = outlined_fixture()
        geometry = BalloonGeometry(source, ink)
        region = dict(box=dict(x=.15, y=.3, width=.5, height=.4), detectedFontSize=45)
        for regions in ([], [region]):
            result = protect_balloon_outlines(ink, regions, geometry)
            self.assertTrue(np.array_equal(result, ink))
            self.assertFalse(np.shares_memory(result, ink))
        with self.assertRaises(ValueError):
            protect_balloon_outlines(ink[:-1], [], geometry)

    def test_solid_and_dashed_borders_on_light_dark_and_colour(self):
        for colour in [(245,)*3, (35,)*3, (210, 185, 235)]:
            for dotted in (False, True):
                source = np.full((800, 800, 3), 145, np.uint8)
                cv2.ellipse(source, (340, 370), (110, 170), 0, 0, 360, colour, -1)
                border = np.zeros(source.shape[:2], np.uint8)
                for start in range(0, 360, 24 if dotted else 360):
                    cv2.ellipse(border, (340, 370), (110, 170), 0, start, start + (12 if dotted else 360), 255, 3)
                foreground = 245 if colour[0] < 100 else 10
                source[border > 0] = foreground
                ink = np.zeros_like(border)
                for top in (300, 345, 390, 435):
                    cv2.putText(ink, "HI", (312, top), cv2.FONT_HERSHEY_SIMPLEX, 1, 255, 3)
                source[ink > 0] = foreground
                region = dict(box=dict(x=310/800, y=275/800, width=50/800, height=165/800), detectedFontSize=30)
                geometry = BalloonGeometry(source, text_mask=ink)
                self.assertIsNotNone(geometry.enclosure(region["box"], 30))
                contaminated = ink | border
                contaminated[640:650, 610:620] = 255
                protected = protect_balloon_outlines(contaminated, [region], geometry)
                self.assertFalse(protected[border > 0].any(), f"Lost border: {colour}, dotted={dotted}")
                self.assertTrue(np.array_equal(protected[ink > 0], ink[ink > 0]))
                self.assertTrue(np.all(protected[640:650, 610:620] == 255), "Neighbouring free text changed")


def jagged_fixture(scale=1):
    source = np.full((700, 700, 3), (170, 190, 170), np.uint8)
    polygon = np.array([(130, 110), (185, 125), (230, 100), (240, 140), (285, 160),
                        (267, 200), (290, 240), (258, 278), (280, 320), (250, 350),
                        (270, 400), (242, 450), (255, 490), (205, 482), (170, 510),
                        (148, 480), (115, 490), (125, 440), (106, 405), (125, 370),
                        (107, 320), (127, 280), (105, 240), (125, 195), (112, 150)])
    cv2.fillPoly(source, [polygon], (210, 185, 235))
    border = np.zeros(source.shape[:2], np.uint8)
    cv2.polylines(border, [polygon], True, 255, 3)
    source[border > 0] = 0
    mask = np.zeros_like(border)
    for y in (205, 305, 405):
        cv2.putText(mask, "OH", (132, y), cv2.FONT_HERSHEY_SIMPLEX, 2.3, 255, 8, cv2.LINE_AA)
    source[mask > 0] = 0
    mask = cv2.dilate(mask, np.ones((3, 3), np.uint8))
    return tuple(cv2.resize(item, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
                 for item in (source, mask, border))


def outlined_fixture():
    source = np.full((160, 310, 3), (72, 55, 50), np.uint8)
    source[:, :120] = (154, 125, 135)
    mask = np.zeros(source.shape[:2], np.uint8)
    for x in (60, 155, 240):
        cv2.ellipse(source, (x, 80), (23, 33), 0, 0, 360, (245,)*3, -1)
        cv2.ellipse(source, (x, 80), (18, 28), 0, 0, 360, (20,)*3, -1)
        if x < 200:
            cv2.ellipse(mask, (x, 80), (18, 28), 0, 0, 360, 255, -1)
    source[20:33, 95:117] = 245
    return source, mask


if __name__ == "__main__":
    unittest.main()
