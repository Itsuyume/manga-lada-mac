"""Edge inputs found by fuzzing the recognition and erasure adapters stay inside their contracts."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
resources = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry, sampled_shape
from balloon_partition import separate_shared_balloons
from dotted_balloon import dotted_contours
from english_regions import observed_ink
from erase_supplemental_text import glyph_mask


def check_boxes_outside_the_page():
    # A cached box starting left of the page used to read mirrored mask columns or
    # hand OpenCV an empty array (a native crash that kills the resident worker).
    page = np.full((100, 100, 3), 255, np.uint8)
    before = page.copy()
    geometry = BalloonGeometry(page, np.zeros((100, 100), np.uint8))
    for box, font in [({"x": -0.01, "y": 0.40, "width": 0.025, "height": 0.10}, 12),
                      ({"x": 0.4, "y": -0.2, "width": 0.1, "height": 0.25}, 12),
                      ({"x": float("inf"), "y": 0.1, "width": 0.1, "height": 0.1}, 12),
                      ({"x": 0.1, "y": 0.1, "width": 0.1, "height": 0.1}, float("nan"))]:
        result = geometry.enclosure(box, font)
        assert result is None or result[0].size, f"Out-of-page box produced an invalid enclosure: {box}"
    assert np.array_equal(page, before), "Geometry changed the source page"


def check_tiny_pages():
    try:
        glyph_mask(np.zeros((1, 7, 3), np.uint8), [{"x": .77, "y": .03, "width": .16, "height": .36}])
    except ValueError:
        pass
    else:
        raise AssertionError("A sub-pixel search area was accepted")
    strip = np.full((2, 3636, 3), 255, np.uint8)
    assert dotted_contours(strip, None, (403, 0, 3125, 2), 1.92) == [], "An extreme scale reached cv2.resize with an empty size"


def check_degenerate_partition():
    outline = np.zeros((40, 60), np.uint8)
    cv2.ellipse(outline, (30, 20), (29, 19), 0, 0, 360, 255, -1)
    shape = sampled_shape(outline, 20, 30, 100, 100, 30)
    upper = {"id": "a", "box": {"x": .45, "y": .29, "width": .10, "height": .02}, "balloonShape": shape}
    lower = {"id": "b", "box": {"x": .45, "y": .30, "width": .10, "height": .05}, "balloonShape": dict(shape)}
    blocks = [upper, lower]
    separate_shared_balloons(blocks)
    for block in blocks:
        part = block["balloonShape"]
        assert part is None or (len(part["rows"]) >= 3 and part["bounds"]["height"] > 0), "A lobe kept a zero-height outline"


def check_line_at_page_edge():
    # Webtoon strips split through balloons put a line against the page edge.
    page = np.full((200, 300, 3), 255, np.uint8)
    cv2.putText(page, "HELLO", (20, 11), cv2.FONT_HERSHEY_SIMPLEX, .5, (0, 0, 0), 1)
    cv2.putText(page, "WORLD", (20, 120), cv2.FONT_HERSHEY_SIMPLEX, .5, (0, 0, 0), 1)
    before = page.copy()
    lines = [{"id": "1", "box": {"x": 20 / 300, "y": 0.0, "width": 50 / 300, "height": 12 / 200}, "originalText": "HELLO", "confidence": 1.0},
             {"id": "2", "box": {"x": 20 / 300, "y": 108 / 200, "width": 50 / 300, "height": 14 / 200}, "originalText": "WORLD", "confidence": 1.0}]
    mask, boxes = observed_ink(page, lines)
    assert mask.shape == page.shape[:2] and mask.dtype == np.uint8, "Edge margin changed the mask geometry"
    ink = page.min(axis=2) < 128
    assert mask[:20][ink[:20]].all(), "Strokes of the line on the page edge were not selected"
    assert not mask[40:90].any(), "The edge margin selected empty paper"
    assert all(0 <= left < right <= 300 and 0 <= top < bottom <= 200 for left, top, right, bottom in boxes), f"Boxes left the page: {boxes}"
    assert np.array_equal(page, before), "Ink selection changed the source page"
    inner_only, _ = observed_ink(page, lines[1:])
    assert np.array_equal(inner_only[100:130], mask[100:130]), "The edge margin changed an inner line's mask"


check_boxes_outside_the_page()
check_tiny_pages()
check_degenerate_partition()
check_line_at_page_edge()
print("Edge input checks passed: out-of-page/non-finite boxes, tiny pages, extreme scales, degenerate lobes, lines on the page edge, source preserved")
