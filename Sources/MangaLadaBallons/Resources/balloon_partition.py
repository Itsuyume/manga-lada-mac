"""Partition existing contours by OCR anchors; never infer a new enclosure or translate text."""
def horizontal_neck(shape: dict, x: float, other_x: float) -> bool:
    def height_at(column):
        return sum(row["left"] <= column <= row["right"] for row in shape["rows"])
    return height_at((x + other_x) / 2) < height_at(x) * .85


def shared_contour(first: dict, second: dict) -> bool:
    a, b = first["bounds"], second["bounds"]
    width = max(0, min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"]))
    height = max(0, min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"]))
    return width * height > max(a["width"] * a["height"], b["width"] * b["height"]) * .95


def separate_shared_balloons(blocks: list[dict]) -> None:
    original_shapes = {block["id"]: block.get("balloonShape") for block in blocks}
    for block in blocks:
        shape = original_shapes[block["id"]]
        if shape is None:
            continue
        bounds = shape["bounds"]
        x = block["box"]["x"] + block["box"]["width"] / 2
        y = block["box"]["y"] + block["box"]["height"] / 2
        left, top, right, bottom = bounds["x"], bounds["y"], bounds["x"] + bounds["width"], bounds["y"] + bounds["height"]
        for other in blocks:
            other_shape = original_shapes[other["id"]]
            if other["id"] == block["id"] or other_shape is None or not shared_contour(shape, other_shape):
                continue
            ox = other["box"]["x"] + other["box"]["width"] / 2
            oy = other["box"]["y"] + other["box"]["height"] / 2
            a, b = block["box"], other["box"]
            overlap_y = max(0, min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"]))
            if overlap_y >= min(a["height"], b["height"]) * .65 and not horizontal_neck(shape, x, ox):
                continue  # Parallel Japanese columns in one balloon are merged by the Core boundary.
            if abs(x - ox) / bounds["width"] >= abs(y - oy) / bounds["height"]:
                right = min(right, (x + ox) / 2) if x < ox else right
                left = max(left, (x + ox) / 2) if x >= ox else left
                continue
            bottom = min(bottom, (y + oy) / 2) if y < oy else bottom
            top = max(top, (y + oy) / 2) if y >= oy else top
        rows = [{"y": row["y"], "left": max(left, row["left"]), "right": min(right, row["right"])}
                for row in shape["rows"] if top <= row["y"] <= bottom and min(right, row["right"]) > max(left, row["left"])]
        if not rows:
            block["balloonShape"] = None
            continue
        left, right = min(row["left"] for row in rows), max(row["right"] for row in rows)
        top, bottom = min(row["y"] for row in rows), max(row["y"] for row in rows)
        block["balloonShape"] = {"bounds": {"x": left, "y": top, "width": right - left, "height": bottom - top}, "rows": rows}
