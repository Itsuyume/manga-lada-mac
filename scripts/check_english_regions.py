"""English OCR observations use shared balloon geometry and bounded erasure."""
from copy import deepcopy
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import unittest
import uuid

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry
from english_regions import recognize_blocks, read_regions, observed_ink
from japanese_engine_worker import JapaneseEngine


def line(text, x, y, width=.22, height=.045):
    return dict(id=str(uuid.uuid4()), originalText=text, box=dict(x=x, y=y, width=width, height=height), confidence=.96)


class EnglishRegionsChecks(unittest.TestCase):
    def test_empty_duplicate_invalid_and_cut_lines(self):
        image = np.full((600, 800, 3), 255, np.uint8)
        geometry = BalloonGeometry(image)
        self.assertEqual(recognize_blocks(image, [], [], geometry), [])
        observation = line("Hello!", .1, .1)
        proposal = dict(id=str(uuid.uuid4()), box=dict(x=.15, y=.08, width=.22, height=.15), originalText="")
        with self.assertRaises(ValueError):
            read_regions([proposal], [observation])
        for observations in ([observation, observation], [line("", .1, .1)], [line("bad", -.1, .1)]):
            with self.assertRaises(ValueError):
                recognize_blocks(image, [], observations, geometry)

    def test_multiline_and_neighbouring_balloons_keep_their_own_text(self):
        image = np.full((600, 800, 3), 180, np.uint8)
        for center in [(200, 250), (590, 250)]:
            cv2.ellipse(image, center, (145, 150), 0, 0, 360, (250,) * 3, -1)
            cv2.ellipse(image, center, (145, 150), 0, 0, 360, (0,) * 3, 3)
        observations = [line("FIRST", .16, .29), line("SENTENCE", .16, .35), line("SECOND", .64, .29)]
        for entry in observations:
            cv2.putText(image, entry["originalText"], (int(entry["box"]["x"] * 800), int(entry["box"]["y"] * 600) + 24),
                        cv2.FONT_HERSHEY_SIMPLEX, .75, (0,) * 3, 2)
        before = image.copy(), deepcopy(observations)
        mask, _ = observed_ink(image, observations)
        geometry = BalloonGeometry(image, text_mask=mask)
        result = recognize_blocks(image, [], observations, geometry)
        self.assertEqual([entry["originalText"] for entry in result], ["FIRST SENTENCE", "SECOND"])
        self.assertTrue(all(entry["balloonShape"] is not None for entry in result))
        self.assertTrue(np.array_equal(image, before[0]) and observations == before[1])
        self.assertFalse(mask[95:105].any(), "Balloon boundary erased")
        variable_heights = deepcopy(observations)
        variable_heights[1]["box"]["height"] = .055
        varied_mask, _ = observed_ink(image, variable_heights)
        varied = recognize_blocks(image, [], variable_heights, BalloonGeometry(image, text_mask=varied_mask))
        self.assertEqual([entry["originalText"] for entry in varied], ["FIRST SENTENCE", "SECOND"],
                         "Different native cap heights split the same balloon")
        proposal = deepcopy(result[0]); proposal["userDefinedBounds"] = dict(x=.12, y=.25, width=.3, height=.18)
        reread = read_regions([proposal], observations)
        self.assertEqual(reread[0]["originalText"], "FIRST SENTENCE")
        self.assertEqual(reread[0]["id"], proposal["id"])
        self.assertEqual(reread[0]["userDefinedBounds"], proposal["userDefinedBounds"])

    def test_drawing_inside_panel_is_not_reading_space(self):
        image = np.full((600, 800, 3), 255, np.uint8)
        cv2.rectangle(image, (90, 100), (380, 380), (0,) * 3, 2)
        cv2.line(image, (180, 240), (240, 330), (0,) * 3, 3)
        entry = line("HELLO", .18, .29)
        cv2.putText(image, "HELLO", (144, 198), cv2.FONT_HERSHEY_SIMPLEX, .75, (0,) * 3, 2)
        mask, _ = observed_ink(image, [entry])
        result = recognize_blocks(image, [], [entry], BalloonGeometry(image, text_mask=mask))
        self.assertIsNone(result[0]["balloonShape"], "Panel artwork became a balloon")
        self.assertEqual(result[0]["box"], entry["box"])

    def test_nearby_free_text_keeps_neighbouring_paragraphs_separate(self):
        image = np.full((600, 800, 3), 255, np.uint8)
        entries = [line("FIRST", .1, .1), line("LINE", .1, .16), line("NEIGHBOUR", .65, .1)]
        detected = [SimpleNamespace(xyxy=[75, 55, 265, 130])]
        result = recognize_blocks(image, detected, entries, BalloonGeometry(image))
        self.assertEqual([entry["originalText"] for entry in result], ["FIRST LINE", "NEIGHBOUR"])

    def test_cleanup_refresh_keeps_review_ids_only_for_unchanged_unambiguous_ocr(self):
        image = np.full((600, 800, 3), 255, np.uint8)
        observations = [line("FIRST", .1, .1), line("LINE", .1, .16)]
        geometry = BalloonGeometry(image)
        prior = recognize_blocks(image, [], observations, geometry)
        before = deepcopy(prior)
        refreshed = recognize_blocks(image, [], observations, geometry, prior)
        self.assertEqual(refreshed, prior, "Cleanup update replaced the identity owning the user's review")
        changed = deepcopy(observations); changed[1]["originalText"] = "CHANGED"
        fresh = recognize_blocks(image, [], changed, geometry, prior)
        self.assertNotEqual(fresh[0]["id"], prior[0]["id"], "Changed OCR inherited stale text")
        ambiguous = recognize_blocks(image, [], observations, geometry, prior + prior)
        self.assertNotEqual(ambiguous[0]["id"], prior[0]["id"], "Ambiguous cache identity was reused")
        self.assertEqual(prior, before)

    def test_small_native_line_includes_its_one_pixel_period_but_keeps_the_frame(self):
        image = np.full((80, 160, 3), 255, np.uint8)
        image[25:34, 20:23] = 0
        image[33, 28] = 0
        image[:, 40:42] = 0
        observations = [line("I.", .125, .3, .065, .15)]
        mask, _ = observed_ink(image, observations)
        self.assertEqual(mask[33, 28], 255, "A recognized period survived cleanup")
        self.assertFalse(mask[:, 40:42].any(), "Nearby frame became punctuation")

    def test_dark_paragraph_joins_without_crossing_a_frame(self):
        image = np.full((600, 800, 3), 65, np.uint8)
        entries = [line("FIRST SENTENCE", .1, .1, .65), line("CONTINUES HERE", .1, .16, .6), line("AND ENDS HERE", .1, .22, .6)]
        for entry in entries:
            cv2.putText(image, entry["originalText"], (80, int(entry["box"]["y"] * 600) + 23),
                        cv2.FONT_HERSHEY_SIMPLEX, .75, (255,) * 3, 2)
        mask, _ = observed_ink(image, entries)
        geometry = BalloonGeometry(image, text_mask=mask, exclude_text_from_contours=True)
        result = recognize_blocks(image, [], entries, geometry)
        self.assertEqual([entry["originalText"] for entry in result], ["FIRST SENTENCE CONTINUES HERE AND ENDS HERE"])
        cv2.line(image, (80, 92), (600, 92), (255,) * 3, 3)
        separated = recognize_blocks(image, [], entries, BalloonGeometry(image, text_mask=mask, exclude_text_from_contours=True))
        self.assertEqual([entry["originalText"] for entry in separated], ["FIRST SENTENCE", "CONTINUES HERE AND ENDS HERE"])

    def test_glyph_exclusion_preserves_the_multiline_enclosure_and_source(self):
        image = np.full((600, 800, 3), 160, np.uint8)
        cv2.ellipse(image, (430, 235), (270, 110), 0, 0, 360, (255,) * 3, -1)
        cv2.ellipse(image, (430, 235), (270, 110), 0, 0, 360, (0,) * 3, 3)
        entries = [line("A NEAR EDGE WORD", .30, .24, .35, .05), line("AND ITS SENTENCE", .30, .30, .35, .05), line("STAYS TOGETHER", .30, .36, .35, .05)]
        for entry in entries:
            cv2.putText(image, entry["originalText"], (240, int(entry["box"]["y"] * 600) + 26),
                        cv2.FONT_HERSHEY_SIMPLEX, .75, (0,) * 3, 2)
        before = image.copy()
        mask, _ = observed_ink(image, entries)
        geometry = BalloonGeometry(image, text_mask=mask, exclude_text_from_contours=True)
        result = recognize_blocks(image, [], entries, geometry)
        self.assertEqual(len(result), 1)
        self.assertIsNotNone(result[0]["balloonShape"])
        self.assertGreater(result[0]["balloonShape"]["bounds"]["width"], .5)
        self.assertTrue(np.array_equal(before, image))

    def test_blank_page_and_detected_unreadable_text_take_distinct_paths(self):
        # No models need to be constructed for this worker response. Exercise
        # its actual atomic writer instead of mocking internal processing.
        boundary = JapaneseEngine.__new__(JapaneseEngine)
        boundary.cv2 = cv2
        image = np.full((100, 200, 3), 120, np.uint8)
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "blank.png"
            request = {"opticalCandidates": [], "destination": str(destination)}
            result = boundary.read_english_page(image, [], request)
            self.assertEqual(result, [])
            self.assertTrue(np.array_equal(cv2.imread(str(destination)), image))
            saved = destination.read_bytes()
            unresolved = boundary.read_english_page(image, [SimpleNamespace(xyxy=[20, 20, 100, 60])], request)
            self.assertEqual(unresolved, [], "Unreadable text acquired invented regions")
            self.assertEqual(destination.read_bytes(), saved, "Abstention changed the source pixels")
            self.assertFalse((destination.parent / "recognized.partial.png").exists())
            request["destination"] = str(destination / "invalid.png")
            with self.assertRaises(OSError):
                boundary.read_english_page(image, [], request)


if __name__ == "__main__":
    unittest.main()
