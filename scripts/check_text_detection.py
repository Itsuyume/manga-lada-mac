"""Detection tensor boundary, real crop geometry, deferred work and source preservation."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
resources = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from text_detection import TextDetection, detection_views, distinct_detections, contact_crop_bounds
from manga_text_detector import decode_predictions, verify_detector
from lettering_regions import inspect_detected_lettering


class TextDetectionChecks(unittest.TestCase):
    def setUp(self):
        self.page = np.full((100, 140, 3), 255, np.uint8)
        cv2.putText(self.page, "A", (8, 80), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 0, 0), 3)

    def test_invalid_inputs_and_model(self):
        for invalid in (None, np.zeros((0, 2, 3), np.uint8), np.zeros((20, 20)), np.zeros((20, 20, 3), np.float32)):
            with self.assertRaises(ValueError):
                list(detection_views(invalid))
        for bounds, score, hint in (((0, 0, 0, 4), .5, "text"), ((0, 0, 8, 9), float("nan"), "text"),
                                     ((-1, 0, 5, 8), .5, "text"), ((0, 0, 8, 9), .5, "dialogue")):
            with self.assertRaises(ValueError):
                TextDetection(bounds, score, hint)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/"detector.onnx"
            with self.assertRaises(FileNotFoundError):
                verify_detector(path)
            path.write_bytes(b"untrusted")
            with self.assertRaises(ValueError):
                verify_detector(path)
            self.assertEqual(path.read_bytes(), b"untrusted")

    def test_tensor_errors_propagate(self):
        view = next(detection_views(self.page))
        for invalid in (np.zeros((1, 5, 10)), np.full((1, 6, 10), np.nan), np.full((1, 6, 10), np.inf)):
            with self.assertRaises(ValueError):
                decode_predictions(invalid, view, (140, 100))
        self.assertEqual(decode_predictions(np.zeros((1, 6, 0)), view, (140, 100)), [])
        self.assertEqual(decode_predictions(np.zeros((1, 6, 10)), view, (140, 100)), [])
        broken = np.ones((1, 6, 1)); broken[0, 4] = 1.1
        with self.assertRaises(ValueError):
            decode_predictions(broken, view, (140, 100))
        broken = np.ones((1, 6, 1)); broken[0, 2] = 0
        with self.assertRaises(ValueError):
            decode_predictions(broken, view, (140, 100))

    def test_views_round_trip_and_no_source_mutation(self):
        before = self.page.copy()
        views = list(detection_views(self.page))
        self.assertEqual(len(views), 2)
        for view in views:
            self.assertEqual(view.pixels.shape, (1024, 1024, 3))
            self.assertEqual(view.restore(view.content, (140, 100)), (0, 0, 140, 100))
            self.assertIsNone(view.restore((-20., -20., -10., -10.), (140, 100)))
            x1, y1, x2, y2 = view.content
            tensor = np.array([[(x1+x2)/2, (y1+y2)/2, x2-x1, y2-y1, .05, .85]], np.float32).T[None]
            detected = decode_predictions(tensor, view, (140, 100))
            self.assertEqual(detected[0].bounds, (0, 0, 140, 100))
            self.assertEqual(detected[0].hint, "effect")
        self.assertTrue(np.array_equal(self.page, before))

    def test_large_image_tiles_and_seams(self):
        page = np.full((1801, 2307, 3), 255, np.uint8)
        views = list(detection_views(page))
        self.assertEqual(len(views), 6)
        for view in views[2:]:
            self.assertIsNone(view.restore(view.content, (2307, 1801)), "Internal seam accepted a partial word")
            x1, y1, x2, y2 = view.content
            safe = view.restore((x1+30, y1+30, x2-30, y2-30), (2307, 1801))
            self.assertIsNotNone(safe)
            self.assertGreater(safe[0], view.source[0])
            self.assertLess(safe[2], view.source[2])
        self.assertTrue(np.all(page == 255))

    def test_duplicates_do_not_merge_neighbours(self):
        full = TextDetection((10, 20, 50, 90), .9, "text")
        partial = TextDetection((15, 25, 40, 70), .4, "effect")
        neighbour = TextDetection((52, 21, 75, 65), .8, "text")
        self.assertEqual(distinct_detections([partial, neighbour, full, full]), [full, neighbour])
        self.assertEqual(distinct_detections([]), [])

    def test_neighbour_limited_padding(self):
        for first, second in (((10, 20, 30, 70), (35, 25, 55, 65)),
                              ((10, 20, 30, 70), (30, 25, 55, 65)),
                              ((10, 20, 40, 40), (10, 45, 40, 65))):
            a, b = TextDetection(first, .9, "text"), TextDetection(second, .8, "text")
            ac = contact_crop_bounds(a, [a, b], (100, 100))
            bc = contact_crop_bounds(b, [a, b], (100, 100))
            self.assertTrue(ac[2] <= bc[0] or ac[3] <= bc[1])
            self.assertLessEqual(ac[0], a.bounds[0])
            self.assertGreaterEqual(ac[2], a.bounds[2])
        edge = TextDetection((0, 0, 20, 30), .9, "text")
        self.assertEqual(contact_crop_bounds(edge, [edge], (20, 30)), (0, 0, 20, 30))
        with self.assertRaises(ValueError):
            contact_crop_bounds(edge, [edge], (10, 30))

    def test_ocr_budget_and_errors_do_not_erase_or_translate(self):
        before = self.page.copy()
        proposals = [TextDetection((0, 10, 60, 90), .9, "text"), TextDetection((65, 10, 120, 90), .2, "effect")]
        calls = []
        def reader(crop):  # External OCR boundary only; all crop/consensus code is real.
            calls.append(crop.copy())
            return "バビュン"
        result = inspect_detected_lettering(self.page, reader, lambda _: proposals, limit=1)
        self.assertEqual(len(calls), 2)
        self.assertEqual(result[0]["text"], "バビュン")
        self.assertEqual(result[1]["status"], "deferred")
        self.assertIsNone(result[1]["text"])
        self.assertEqual(result[1]["detectedBounds"], proposals[1].bounds)
        self.assertNotIn("textKind", result[0], "Detector hint became a semantic classification")
        self.assertTrue(np.array_equal(self.page, before))
        self.assertEqual(inspect_detected_lettering(self.page, reader, lambda _: []), [])
        def failed(_):
            raise RuntimeError("external model failure")
        with self.assertRaisesRegex(RuntimeError, "external model failure"):
            inspect_detected_lettering(self.page, failed, lambda _: proposals)
        with self.assertRaisesRegex(RuntimeError, "external model failure"):
            inspect_detected_lettering(self.page, reader, failed)
        for invalid_limit in (-1, 41, None, True):
            with self.assertRaises(ValueError):
                inspect_detected_lettering(self.page, reader, lambda _: proposals, invalid_limit)
        self.assertTrue(np.array_equal(self.page, before))


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
