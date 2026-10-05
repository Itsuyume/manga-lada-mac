"""Optional pinned ONNX detector. Detection only; no erasure, translation or downloads."""
import hashlib
from pathlib import Path
import cv2
import numpy as np
from text_detection import TextDetection, detection_views, distinct_detections

MODEL_ID = "lordtrilink/manga-text-detector-v0"
MODEL_REVISION = "ba686d01c556d4e7c6f382e5d685c7fe75f5dd49"
MODEL_FILE = "best-1024-fp32.onnx"
MODEL_SHA256 = "cddc342a0e1ada5636a30fbf352c7476e8ca276053d95e630ec4aeb537b3a26a"
MODEL_LICENSE = "CC-BY-NC-SA-4.0"


def verify_detector(path: Path) -> None:
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != MODEL_SHA256:
            raise ValueError("Text detector checksum mismatch")


def decode_predictions(output: np.ndarray, view, image_size: tuple[int, int]) -> list[TextDetection]:
    if output.ndim != 3 or output.shape[:2] != (1, 6) or not np.isfinite(output).all():
        raise ValueError("Unexpected text detector tensor")
    rows = output[0].T
    if np.any(rows[:, 4:] < 0) or np.any(rows[:, 4:] > 1):
        raise ValueError("Invalid detector scores")
    scores = rows[:, 4:].max(axis=1)
    labels = rows[:, 4:].argmax(axis=1)
    eligible = scores >= .05
    rows, scores, labels = rows[eligible], scores[eligible], labels[eligible]
    if not len(rows):
        return []
    boxes = rows[:, :4].copy()
    if np.any(boxes[:, 2:] <= 0):
        raise ValueError("Invalid detector extents")
    boxes[:, :2] -= boxes[:, 2:]/2
    keep = cv2.dnn.NMSBoxes(boxes.tolist(), scores.tolist(), .05, .7)
    result = []
    for index in keep:
        x, y, width, height = boxes[index]
        bounds = view.restore((float(x), float(y), float(x+width), float(y+height)), image_size)
        if bounds is not None:
            result.append(TextDetection(bounds, float(scores[index]), "effect" if labels[index] else "text"))
    return result


class MangaTextDetector:
    """CPU OpenCV DNN, explicit local model, reused across requests. Class hints are unverified."""
    def __init__(self, model: Path):
        verify_detector(model)
        self.net = cv2.dnn.readNetFromONNX(str(model))
        self.net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
        self.net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

    def __call__(self, image: np.ndarray) -> list[TextDetection]:
        candidates = []
        for view in detection_views(image):
            self.net.setInput(cv2.dnn.blobFromImage(view.pixels, 1/255., swapRB=True))
            candidates.extend(decode_predictions(self.net.forward(), view, image.shape[1::-1]))
        return distinct_detections(candidates)
