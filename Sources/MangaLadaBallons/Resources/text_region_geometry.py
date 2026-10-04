"""Normalized rectangle validation and overlap at the image-model boundary."""
import math


def validate_box(box: dict) -> None:
    x, y, w, h = (box[key] for key in ("x", "y", "width", "height"))
    if not all(math.isfinite(value) for value in (x, y, w, h)) or min(x, y) < 0 or min(w, h) <= 0 or x + w > 1.000001 or y + h > 1.000001:
        raise ValueError("Invalid optical rectangle")


def intersection_area(first: dict, second: dict) -> float:
    width = max(0, min(first["x"] + first["width"], second["x"] + second["width"]) - max(first["x"], second["x"]))
    height = max(0, min(first["y"] + first["height"], second["y"] + second["height"]) - max(first["y"], second["y"]))
    return width * height


def overlaps(first: dict, second: dict) -> bool:
    return intersection_area(first, second) > min(first["width"] * first["height"], second["width"] * second["height"]) * .25


def rectangular_enclosure(shape: dict) -> bool:
    """Recognized near-rectangular interiors, independent of glyph/background color."""
    rows, bounds = shape["rows"], shape["bounds"]
    width = bounds["width"]
    coverage = sum(row["right"] - row["left"] for row in rows) / (len(rows) * width)
    left_spread = max(row["left"] for row in rows) - min(row["left"] for row in rows)
    right_spread = max(row["right"] for row in rows) - min(row["right"] for row in rows)
    return coverage >= .97 and max(left_spread, right_spread) <= width * .06
