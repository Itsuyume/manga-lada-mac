"""Read-only text proposals, coordinate transforms and neighbour-limited OCR crops."""
from dataclasses import dataclass
import math
from typing import Iterator, Literal
import cv2
import numpy as np
from text_region_geometry import intersection_area, validate_bgr_image


@dataclass(frozen=True)
class TextDetection:
    bounds: tuple[int, int, int, int]
    score: float
    hint: Literal["text", "effect"]

    def __post_init__(self):
        x1, y1, x2, y2 = self.bounds
        if not all(isinstance(v, int) for v in self.bounds) or min(x1, y1) < 0 or x2 <= x1 or y2 <= y1:
            raise ValueError("Invalid text detection bounds")
        if not math.isfinite(self.score) or not 0 <= self.score <= 1 or self.hint not in ("text", "effect"):
            raise ValueError("Invalid text detection evidence")

    @property
    def rectangle(self) -> dict:
        x1, y1, x2, y2 = self.bounds
        return dict(x=x1, y=y1, width=x2-x1, height=y2-y1)


@dataclass(frozen=True)
class DetectionView:
    pixels: np.ndarray
    source: tuple[int, int, int, int]
    content: tuple[int, int, int, int]

    def restore(self, bounds, image_size: tuple[int, int]) -> tuple[int, int, int, int] | None:
        if len(bounds) != 4 or not all(math.isfinite(v) for v in bounds):
            raise ValueError("Detector returned non-finite coordinates")
        if bounds[2] <= bounds[0] or bounds[3] <= bounds[1]:
            raise ValueError("Detector returned an inverted rectangle")
        sx1, sy1, sx2, sy2 = self.source
        cx1, cy1, cx2, cy2 = self.content
        scale_x, scale_y = (sx2-sx1)/(cx2-cx1), (sy2-sy1)/(cy2-cy1)
        raw = ((bounds[0]-cx1)*scale_x+sx1, (bounds[1]-cy1)*scale_y+sy1,
               (bounds[2]-cx1)*scale_x+sx1, (bounds[3]-cy1)*scale_y+sy1)
        width, height = image_size
        # Reject partial words cut by an internal tile seam. Full-page edges remain valid.
        if ((sx1 > 0 and raw[0] <= sx1+2*scale_x) or (sy1 > 0 and raw[1] <= sy1+2*scale_y)
                or (sx2 < width and raw[2] >= sx2-2*scale_x) or (sy2 < height and raw[3] >= sy2-2*scale_y)):
            return None
        clipped = (max(sx1, math.floor(raw[0])), max(sy1, math.floor(raw[1])),
                   min(sx2, math.ceil(raw[2])), min(sy2, math.ceil(raw[3])))
        return clipped if min(clipped[2]-clipped[0], clipped[3]-clipped[1]) >= 2 else None


def detector_view(image: np.ndarray, bounds: tuple[int, int, int, int], margin: float = 0.) -> DetectionView:
    x1, y1, x2, y2 = bounds
    width, height = x2-x1, y2-y1
    pad = round(max(width, height)*margin)
    scale = 1024/max(width+2*pad, height+2*pad)
    content_width, content_height = max(1, round(width*scale)), max(1, round(height*scale))
    outer_width, outer_height = round((width+2*pad)*scale), round((height+2*pad)*scale)
    left, top = (1024-outer_width)//2, (1024-outer_height)//2
    canvas = np.full((1024, 1024, 3), 114, np.uint8)
    if pad:
        canvas[top:top+outer_height, left:left+outer_width] = 255
    left += (outer_width-content_width)//2
    top += (outer_height-content_height)//2
    canvas[top:top+content_height, left:left+content_width] = cv2.resize(image[y1:y2, x1:x2], (content_width, content_height))
    return DetectionView(canvas, bounds, (left, top, left+content_width, top+content_height))


def detection_views(image: np.ndarray) -> Iterator[DetectionView]:
    """At most six fixed-size views, preserving aspect ratio and original coordinates."""
    validate_bgr_image(image)
    height, width = image.shape[:2]
    whole = (0, 0, width, height)
    yield detector_view(image, whole)
    yield detector_view(image, whole, margin=.5)
    if max(width, height) <= 1600:
        return
    tile_width, tile_height = math.ceil(width*.6), math.ceil(height*.6)
    for top in sorted({0, height-tile_height}):
        for left in sorted({0, width-tile_width}):
            yield detector_view(image, (left, top, left+tile_width, top+tile_height))


def distinct_detections(detections: list[TextDetection]) -> list[TextDetection]:
    """Suppress repeated/contained proposals; never join neighbouring speech bubbles."""
    selected = []
    for candidate in sorted(detections, key=lambda item: (-item.score, item.bounds)):
        first = candidate.rectangle
        duplicate = False
        for other in selected:
            second = other.rectangle
            intersection = intersection_area(first, second)
            smaller = min(first["width"]*first["height"], second["width"]*second["height"])
            if intersection >= smaller*.8:
                duplicate = True
                break
        if not duplicate:
            selected.append(candidate)
    return selected


def contact_crop_bounds(target: TextDetection, neighbours: list[TextDetection], image_size: tuple[int, int]) -> tuple[int, int, int, int]:
    """Expand by 30% of the short side, stopping halfway to another detected region."""
    x1, y1, x2, y2 = target.bounds
    width, height = image_size
    if x2 > width or y2 > height or any(n.bounds[2] > width or n.bounds[3] > height for n in neighbours):
        raise ValueError("Text detection lies outside the image")
    pad = max(2., min(x2-x1, y2-y1)*.3)
    left, top, right, bottom = min(pad, x1), min(pad, y1), min(pad, width-x2), min(pad, height-y2)
    for other in neighbours:
        if other == target:
            continue
        ox1, oy1, ox2, oy2 = other.bounds
        if oy2 > y1-pad and oy1 < y2+pad:
            if ox2 <= x1:
                left = min(left, (x1-ox2)/2)
            if ox1 >= x2:
                right = min(right, (ox1-x2)/2)
        if ox2 > x1-pad and ox1 < x2+pad:
            if oy2 <= y1:
                top = min(top, (y1-oy2)/2)
            if oy1 >= y2:
                bottom = min(bottom, (oy1-y2)/2)
    # Round toward the core so adjacent crops cannot gain a shared boundary pixel.
    return math.ceil(x1-left), math.ceil(y1-top), math.floor(x2+right), math.floor(y2+bottom)
