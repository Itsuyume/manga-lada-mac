"""Optional decorative-stroke segmentation, corroborated by source OCR.

Model masks and predicted IoUs alone never authorize erasing artwork. This
boundary supports substantial lettering on a contrasting background.
"""
import hashlib
import math
from pathlib import Path
from typing import Callable
import cv2
import numpy as np
from lettering_ocr import normalized_reading
from text_region_geometry import validate_bgr_image

MODEL_ID = "opencv/opencv_zoo"
MODEL_REVISION = "d4938dfc9d4ec5d098bfa33e98b3f3345a236586"
MODEL_DIRECTORY = "models/image_segmentation_efficientsam"
MODEL_FILE = "image_segmentation_efficientsam_ti_2025april.onnx"
MODEL_SHA256 = "4eb496e0a7259d435b49b66faf1754aa45a5c382a34558ddda9a8c6fe5915d77"


def verify_stroke_model(path: Path) -> None:
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != MODEL_SHA256:
            raise ValueError("Lettering stroke model checksum mismatch")


def stroke_contrast(image: np.ndarray) -> np.ndarray:
    """Normalize bright ink for segmentation only; keep original pixel coordinates."""
    validate_bgr_image(image)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    border = np.concatenate((gray[0], gray[-1], gray[:, 0], gray[:, -1]))
    return 255-image if np.median(border) < 128 else image.copy()


def stroke_points(image: np.ndarray, bounds: tuple[int, int, int, int]) -> list[list[int]]:
    """Foreground prompts come from substantial dark cores inside the text proposal."""
    validate_bgr_image(image)
    height, width = image.shape[:2]
    if len(bounds) != 4 or any(type(value) is not int for value in bounds):
        raise ValueError("Stroke proposal requires four integer coordinates")
    left, top, right, bottom = bounds
    if not 0 <= left < right <= width or not 0 <= top < bottom <= height:
        raise ValueError("Stroke proposal escapes its source crop")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    dark = np.zeros_like(gray)
    dark[top:bottom, left:right] = gray[top:bottom, left:right] < 100
    distance = cv2.distanceTransform(dark, cv2.DIST_L2, 5)
    _, labels, stats, _ = cv2.connectedComponentsWithStats((distance > 2).astype(np.uint8), 8)
    points = []
    for label in np.argsort(stats[1:, 4])[::-1][:4] + 1:
        row, column = np.unravel_index(np.argmax(np.where(labels == label, distance, 0)), distance.shape)
        points.append([int(column), int(row)])
    return points


def confirmed_strokes(image: np.ndarray, source_text: str, masks: list[np.ndarray],
                      recognize: Callable[[np.ndarray], str]) -> np.ndarray | None:
    """Reject background masks and partial readings before bounded edge completion.

The caller must supply a previously corroborated source reading. Isolated-stroke
OCR is additional evidence, never a replacement for that source reading.
"""
    image = stroke_contrast(image)
    if not source_text or len(masks) > 3:
        raise ValueError("Stroke confirmation needs a source reading and at most three masks")
    for mask in masks:
        if mask.dtype != np.uint8 or mask.shape != image.shape[:2] or not np.isin(mask, (0, 255)).all():
            raise ValueError("Stroke segmentation returned an invalid binary mask")
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    eligible = []
    for mask in masks:
        selected = mask > 0
        amount = int(np.count_nonzero(selected))
        if not 16 <= amount <= gray.size * .45:
            continue
        if np.count_nonzero(selected & (gray < 100)) < amount * .95:
            continue  # A balloon/illustration silhouette is not a glyph mask.
        eligible.append(mask)
    for mask in sorted(eligible, key=np.count_nonzero, reverse=True):
        isolated = np.full_like(image, 255)
        isolated[mask > 0] = image[mask > 0]
        if normalized_reading(recognize(isolated)) != normalized_reading(source_text):
            continue  # Missing accents or complete characters can still look plausible.
        return complete_stroke_edges(gray, mask)
    return None


def complete_stroke_edges(gray: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Complete observed opposite-color shadows attached to corroborated ink.

    Work in normalized dark-ink polarity. A shadow must contrast with measured
    background, stay near the glyph and remain independent of crop-edge artwork.
    """
    radius = min(3, max(1, math.ceil(max(gray.shape) / 256)))
    completed = cv2.dilate(mask, np.ones((2 * radius + 1, 2 * radius + 1), np.uint8))
    border = np.concatenate((gray[0], gray[-1], gray[:, 0], gray[:, -1]))
    background = float(np.median(border))
    variation = float(np.median(np.abs(border.astype(float) - background)))
    threshold = background + max(12, variation * 4)
    if variation > 12 or threshold >= 255:
        return completed
    depth = cv2.distanceTransform(completed, cv2.DIST_L2, 5)
    reach = max(radius * 3, math.ceil(np.percentile(depth[completed > 0], 90)))
    distance = cv2.distanceTransform((completed == 0).astype(np.uint8), cv2.DIST_L2, 5)
    connected = ((completed > 0) | (gray > threshold)).astype(np.uint8)
    _, labels, stats, _ = cv2.connectedComponentsWithStats(connected, 8)
    shadows = np.zeros_like(mask)
    height, width = gray.shape
    # Inspect only components touching confirmed ink, not every texture speck.
    for index in np.unique(labels[completed > 0]):
        x, y, w, h, amount = stats[index]
        if x <= 1 or y <= 1 or x+w >= width-1 or y+h >= height-1:
            continue
        selected = labels == index
        evidence = np.count_nonzero(selected & (completed > 0))
        if not evidence or amount > evidence * 2 or distance[selected].max() > reach:
            continue
        shadows[selected] = 255
    return completed | cv2.dilate(shadows, np.ones((3, 3), np.uint8))


class LetteringStrokeSegmenter:
    """Pinned local EfficientSAM, explicit CPU inference, no runtime downloads."""
    def __init__(self, model: Path):
        verify_stroke_model(model)
        self.net = cv2.dnn.readNetFromONNX(str(model))
        self.net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
        self.net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

    def __call__(self, image: np.ndarray, bounds: tuple[int, int, int, int]) -> list[np.ndarray]:
        image = stroke_contrast(image)
        seeds = stroke_points(image, bounds)
        if not seeds:
            return []
        height, width = image.shape[:2]
        side = max(height, width)
        scaled_width, scaled_height = max(1, round(width * 1024 / side)), max(1, round(height * 1024 / side))
        canvas = np.full((1024, 1024, 3), 255, np.uint8)
        canvas[:scaled_height, :scaled_width] = cv2.resize(image, (scaled_width, scaled_height))
        blob = cv2.dnn.blobFromImage(canvas, 1 / 255., swapRB=True)
        left, top, right, bottom = bounds
        coordinates = [[left, top], [right, bottom]] + seeds
        points = np.zeros((1, 1, 6, 2), np.float32)
        labels = np.full((1, 1, 6, 1), -1, np.float32)
        points[0, 0, :len(coordinates)] = np.asarray(coordinates, np.float32) * 1024 / side
        labels[0, 0, :len(coordinates), 0] = [2, 3] + [1] * len(seeds)
        for name, value in [("batched_images", blob), ("batched_point_coords", points), ("batched_point_labels", labels)]:
            self.net.setInput(value, name)
        masks = self.net.forward(["output_masks"])[0]
        if masks.ndim != 5 or masks.shape[:3] != (1, 1, 3) or not np.isfinite(masks).all():
            raise ValueError("Unexpected lettering stroke model output")
        return [cv2.resize((mask >= 0).astype(np.uint8) * 255, (side, side), interpolation=cv2.INTER_NEAREST)[:height, :width]
                for mask in masks[0, 0]]
