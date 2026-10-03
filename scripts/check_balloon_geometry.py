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
print("Balloon geometry checks passed: source outlines, curved/pastel/dark interiors, separate joined lobes, blank/artwork rejection, source preserved")
