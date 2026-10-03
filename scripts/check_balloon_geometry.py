#!/usr/bin/env python3
"""Behavior checks for curved, open and empty balloon interiors."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"))
import cv2
import numpy as np
from balloon_geometry import balloon_shape
from balloon_geometry import BalloonGeometry, separate_shared_balloons

image = np.full((640, 640, 3), 255, dtype=np.uint8)
cv2.ellipse(image, (320, 320), (110, 140), 0, 0, 360, (0, 0, 0), 4)
original = image.copy()
box = {"x": 280 / 640, "y": 250 / 640, "width": 80 / 640, "height": 140 / 640}
shape = balloon_shape(image, box, 40)
assert shape is not None, "Closed balloon interior was not found"
assert BalloonGeometry(image, text_mask=np.zeros(image.shape[:2], np.uint8)).shape(box, 40) == shape, "An empty ink mask changed rectangle-based detection"
try:
    BalloonGeometry(image, text_mask=np.zeros((10, 10), np.uint8))
except ValueError as error:
    assert "dimensions" in str(error)
else:
    raise AssertionError("A mask with different page dimensions was accepted")
assert np.array_equal(image, original), "Geometry detection changed source pixels"
widths = [row["right"] - row["left"] for row in shape["rows"]]
assert widths[len(widths) // 2] > widths[4] * 1.3, "Curved balloon was reduced to a rectangle"
assert .32 < shape["bounds"]["x"] < .35 and .27 < shape["bounds"]["y"] < .30
assert balloon_shape(np.full_like(image, 255), box, 40) is None, "Unbounded blank page became a balloon"
assert balloon_shape(np.zeros_like(image), box, 40) is None, "Black artwork became a balloon"
assert balloon_shape(image, box, 40, original=np.full_like(image, 145)) is None, "Erased text on gray artwork became a balloon"
assert balloon_shape(np.full_like(image, 255), box, 40, original=image) is not None, "Erased outlines changed the source balloon's boundary"
dark = np.full_like(image, 145)
cv2.rectangle(dark, (210, 190), (430, 450), (35, 35, 35), -1)
assert balloon_shape(dark, box, 40) is not None, "Black caption box was rejected"
for color in [(250, 235, 215), (220, 225, 250)]:
    colored = np.full_like(image, 145)
    cv2.ellipse(colored, (320, 320), (110, 140), 0, 0, 360, color, -1)
    cv2.ellipse(colored, (320, 320), (110, 140), 0, 0, 360, (0, 0, 0), 4)
    assert balloon_shape(colored, box, 40, original=colored) is not None, "Pastel balloon was rejected as artwork"
cv2.rectangle(image, (280, 285), (330, 355), (0, 0, 0), -1)
assert balloon_shape(image, box, 40) is None, "Artwork at the text seed was treated as writable space"
notched_art = np.full_like(image, 145)
cv2.rectangle(notched_art, (210, 190), (430, 450), (250, 250, 250), -1)
cv2.rectangle(notched_art, (210, 275), (320, 300), (145, 145, 145), -1)
cv2.rectangle(notched_art, (320, 340), (430, 365), (145, 145, 145), -1)
assert balloon_shape(notched_art, box, 40) is None, "Broken text halos or artwork became a balloon interior"
panel = np.full_like(image, 255)
cv2.rectangle(panel, (64, 220), (576, 365), (0, 0, 0), 4)
cv2.rectangle(panel, (280, 250), (365, 320), (0, 0, 0), -1)
panel_text = {"x": 500 / 640, "y": 250 / 640, "width": 55 / 640, "height": 75 / 640}
assert balloon_shape(panel, panel_text, 25) is None, "Panel border relocated right-hand dialogue onto the character's face"
centered_panel = np.full_like(image, 255)
cv2.rectangle(centered_panel, (64, 220), (576, 365), (0, 0, 0), 4)
cv2.rectangle(centered_panel, (170, 245), (240, 335), (0, 0, 0), -1)
centered_text = {"x": 292 / 640, "y": 250 / 640, "width": 55 / 640, "height": 75 / 640}
assert balloon_shape(centered_panel, centered_text, 25) is None, "Panel border became a balloon even when the dialogue was near its center"
jagged = np.full_like(image, 145)
polygon = np.array([(420, 200), (570, 200), (570, 310), (520, 310), (520, 430), (420, 430)])
cv2.fillPoly(jagged, [polygon], (255, 255, 255))
cv2.polylines(jagged, [polygon], True, (0, 0, 0), 3)
ink = np.zeros(image.shape[:2], np.uint8)
for left, top, right, bottom in [(540, 220, 548, 260), (485, 270, 493, 340), (440, 350, 448, 410)]:
    cv2.rectangle(ink, (left, top), (right, bottom), 255, -1)
jagged[ink > 0] = 0
jagged_text = {"x": 432 / 640, "y": 214 / 640, "width": 130 / 640, "height": 200 / 640}
source_before, ink_before = jagged.copy(), ink.copy()
jagged_shape = BalloonGeometry(jagged, text_mask=ink).shape(jagged_text, 25)
assert np.array_equal(jagged, source_before) and np.array_equal(ink, ink_before), "Glyph containment altered the source image or OCR mask"
assert jagged_shape is not None, "Staggered Japanese columns in a jagged balloon were rejected by their rectangular bounding box"
upper = next(row for row in jagged_shape["rows"] if row["y"] >= .4)
lower = next(row for row in jagged_shape["rows"] if row["y"] >= .6)
assert lower["right"] < upper["right"] - .05, "Jagged balloon lost the narrower lower interior"
wrong_ink = ink.copy()
wrong_ink[350:405, 535:555] = 255
assert BalloonGeometry(jagged, text_mask=wrong_ink).shape(jagged_text, 25) is None, "A candidate excluding actual source letters was accepted"
diagonal = np.full_like(image, 145)
lobes = np.zeros(image.shape[:2], np.uint8)
cv2.ellipse(lobes, (375, 170), (80, 105), 0, 0, 360, 255, -1)
cv2.ellipse(lobes, (250, 300), (105, 118), 0, 0, 360, 255, -1)
diagonal[lobes > 0] = (240, 230, 250)
outlines, _ = cv2.findContours(lobes, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
cv2.drawContours(diagonal, outlines, -1, (0, 0, 0), 3)
diagonal_geometry = BalloonGeometry(diagonal)
diagonal_blocks = [{"id": str(i), "box": {"x": x / 640, "y": y / 640, "width": 35 / 640, "height": 140 / 640}}
                   for i, (x, y) in enumerate([(357, 95), (230, 230)])]
for block in diagonal_blocks:
    block["balloonShape"] = diagonal_geometry.shape(block["box"], 32)
    assert block["balloonShape"] is not None, "Panel rejection also rejected a narrow-text lobe in a diagonally joined balloon"
separate_shared_balloons(diagonal_blocks)
assert diagonal_blocks[0]["balloonShape"]["bounds"] != diagonal_blocks[1]["balloonShape"]["bounds"], "Diagonal lobes still share the whole compound balloon"
joined_mask = np.zeros((640, 640), np.uint8)
cv2.ellipse(joined_mask, (265, 320), (90, 125), 0, 0, 360, 255, -1)
cv2.ellipse(joined_mask, (375, 320), (90, 125), 0, 0, 360, 255, -1)
joined = np.full_like(image, 145)
joined[joined_mask > 0] = (240, 230, 250)
contours, _ = cv2.findContours(joined_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
cv2.drawContours(joined, contours, -1, (0, 0, 0), 3)
geometry = BalloonGeometry(joined)
blocks = [{"id": str(i), "box": {"x": x / 640, "y": 280 / 640, "width": 45 / 640, "height": 80 / 640}} for i, x in enumerate((240, 350))]
for block in blocks:
    block["balloonShape"] = geometry.shape(block["box"], 35)
    assert block["balloonShape"] is not None, "Joined balloon lobe was missed"
separate_shared_balloons(blocks)
left, right = (block["balloonShape"] for block in blocks)
assert left["bounds"]["x"] + left["bounds"]["width"] <= right["bounds"]["x"], "Joined bubbles share translation space"
assert all(row["right"] <= right["bounds"]["x"] for row in left["rows"]), "Curved line widths escaped their own lobe"
for block in blocks:
    block["balloonShape"] = geometry.shape(block["box"], 35)
blocks[1]["balloonShape"]["bounds"]["x"] -= 1 / 640
blocks[1]["balloonShape"]["bounds"]["width"] += 1 / 640
separate_shared_balloons(blocks)
assert blocks[0]["balloonShape"]["bounds"]["x"] + blocks[0]["balloonShape"]["bounds"]["width"] <= blocks[1]["balloonShape"]["bounds"]["x"], "One-pixel contour variation merged distinct dialogue lobes"
columns = [{"id": str(i), "box": {"x": x / 640, "y": 280 / 640, "width": 15 / 640, "height": 80 / 640}} for i, x in enumerate((305, 330))]
plain = np.full_like(image, 255)
cv2.ellipse(plain, (320, 320), (110, 140), 0, 0, 360, (0, 0, 0), 4)
g = BalloonGeometry(plain)
for block in columns:
    block["balloonShape"] = g.shape(block["box"], 35)
separate_shared_balloons(columns)
assert columns[0]["balloonShape"]["bounds"] == columns[1]["balloonShape"]["bounds"], "Japanese columns in one balloon were split into false lobes"
edge = np.full_like(image, 255)
cv2.ellipse(edge, (320, 30), (110, 140), 0, 0, 360, (0, 0, 0), 4)
edge_shape = balloon_shape(edge, {"x": 300 / 640, "y": 10 / 640, "width": 40 / 640, "height": 80 / 640}, 35)
assert edge_shape is not None and edge_shape["bounds"]["y"] < .01, "Balloon clipped at the page edge was lost"
print("Balloon geometry checks passed: source outlines, curved/pastel/dark/staggered interiors, joined lobes, panel/art rejection, empty/invalid masks, source preserved")
