"""Local JSON-lines adapter. Models stay resident for the whole book."""
import contextlib
from copy import deepcopy
import json
import os
from pathlib import Path
import sys
import time
import traceback
import uuid
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ballontranslator.utils.textblock import TextBlock

sys.dont_write_bytecode = True

protocol_output = sys.stdout


class JapaneseEngine:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.lettering = None
        sys.path.insert(0, str(root))
        os.chdir(root)
        import cv2
        import torch
        from ballontranslator.modules.textdetector.detector_ctd import ComicTextDetector
        from ballontranslator.modules.ocr.ocr_manga import MangaOCR
        from ballontranslator.modules.inpaint.inpaint_default import LamaLarge
        from ballontranslator.utils.config import pcfg

        torch.set_num_threads(4)
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        pcfg.module.filter_mask_by_bboxes = True
        self.cv2 = cv2
        self.detector = ComicTextDetector(device="cpu", detect_size=1024)
        # Upstream parameter patching shares nested dictionaries between instances.
        # Snapshot before constructing the second detector so it cannot reconfigure the first.
        self.detector.params = deepcopy(self.detector.params)
        self.detail_detector = ComicTextDetector(device=device, detect_size=2048) if device == "mps" else None
        if self.detail_detector is not None:
            self.detail_detector.params = deepcopy(self.detail_detector.params)
        if self.detector.device != "cpu" or self.detector.detect_size != 1024:
            raise RuntimeError("Coarse detector configuration was changed by another model")
        self.ocr = MangaOCR(device=device)
        self.painter = LamaLarge(device=device, inpaint_size=1536, precision="fp32")
        # The library's white-background shortcut mistakes outlined text for empty balloons.
        self.painter.check_need_inpaint = False

    def process(self, request: dict) -> dict:
        began = time.monotonic()
        from region_ocr import validate_backend
        backend = validate_backend(request.get("ocrBackend", "manga"))
        image = self.cv2.imread(request["source"], self.cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("Cannot decode source image")
        if "letteringOnly" in request:
            return {"lettering": self.read_lettering_only(image, request["letteringOnly"])}
        if request.get("regions") is not None:
            return {"blocks": self.read_proposed_regions(image, request["regions"], backend)}
        height, width = image.shape[:2]
        mask, detected = self.detector.detect(image)
        if self.detail_detector is not None:
            from detection_refinement import refine_detection
            detail_mask, details = self.detail_detector.detect(image)
            mask, detected = refine_detection(image, mask, detected, detail_mask, details)
        from balloon_recovery import recover_balloons
        mask, detected = recover_balloons(image, mask, detected, self.detector.detect, request.get("blocks"),
                                         connected_lettering=backend == "hayai")
        from balloon_lobes import detect_lobes, retain_cached_regions, source_rectangle
        lobes = detect_lobes(image, mask, detected)
        detected = lobes.blocks
        self.prepare_title_mask(image, mask, detected)
        blocks = request.get("blocks")
        if blocks is None:
            blocks = self.read_blocks(image, detected, backend)
        else:
            from detection_refinement import missing_detections
            blocks = retain_cached_regions(blocks, lobes.replaced, width, height)
            if request.get("rereadExisting") is True:
                blocks = self.reread_existing(image, blocks, backend)
            additions = missing_detections(detected, blocks, width, height)
            if additions:
                blocks = blocks + self.read_blocks(image, additions, backend)
        optical_mask, optical_boxes = self.add_optical_effects(image, blocks, request, backend)
        mask = self.cv2.bitwise_or(mask, optical_mask)
        from balloon_geometry import BalloonGeometry
        from balloon_partition import separate_shared_balloons
        from text_region_kind import classify_text_kind
        geometry = BalloonGeometry(image, text_mask=mask.copy())
        sound_effect_sources = set(request["soundEffectSources"])
        for block in blocks:
            bounds = source_rectangle(block["box"], width, height)
            block["balloonShape"] = lobes.shapes[bounds] if bounds in lobes.shapes else geometry.shape(block["box"], block["detectedFontSize"])
            kind = classify_text_kind(block, sound_effect_sources, request["soundEffectPatterns"])
            if kind is not None:
                block["textKind"] = kind
        separate_shared_balloons(blocks)
        punctuation_mask, punctuation_boxes = self.add_sentence_punctuation(image, blocks)
        mask = self.cv2.bitwise_or(mask, punctuation_mask)
        self.expand_outline_mask(image, mask, detected)
        paint_blocks = self.inpainting_blocks(detected, width, height) + self.inpainting_regions(optical_boxes + punctuation_boxes)
        from flat_background import prepare_flat_backgrounds
        prepared, pending = prepare_flat_backgrounds(image, image, mask, [block.xyxy for block in paint_blocks])
        unresolved = [block for block in paint_blocks if pending[block.xyxy[1]:block.xyxy[3], block.xyxy[0]:block.xyxy[2]].any()]
        result = self.painter.inpaint(prepared, pending.copy(), unresolved, check_need_inpaint=False) if unresolved else prepared.copy()
        result[pending == 0] = prepared[pending == 0]
        destination = Path(request["destination"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name("recognized.partial.png")
        if not self.cv2.imwrite(str(temporary), result):
            raise OSError("Cannot save clean page")
        os.replace(temporary, destination)
        return {"blocks": blocks, "elapsed": time.monotonic() - began}

    def read_lettering_only(self, image, mode: str) -> list[dict]:
        from lettering_regions import inspect_lettering_regions
        return inspect_lettering_regions(image, self.recognize_lettering, mode)

    def recognize_lettering(self, crop):
        from hayai_lettering import HayaiLetteringOCR
        if self.lettering is None:
            import torch
            device = "mps" if torch.backends.mps.is_available() else "cpu"
            self.lettering = HayaiLetteringOCR(self.root.parent / "LetteringOCR", device)
        return self.lettering(crop)

    def read_region(self, crop, backend: str) -> dict:
        from region_ocr import recognize_region
        if backend == "hayai":
            return recognize_region(crop, self.recognize_lettering, backend)
        self.ocr.load_model()
        return recognize_region(crop, self.ocr.ocr_img, backend)

    def add_optical_effects(self, image, blocks: list[dict], request: dict, backend: str) -> tuple:
        from optical_effects import plan_effects, confirmed_effects, effect_mask
        proposals, matched = plan_effects(blocks, request["opticalCandidates"],
                                          set(request["soundEffectSources"]), request["soundEffectPatterns"])
        verified = []
        for start in range(0, len(proposals), 40):
            readings = self.read_proposed_regions(image, proposals[start:start + 40], backend)
            verified.extend(block for block in readings if block.get("recognitionAlternatives") is None)
        extras = confirmed_effects(proposals, verified)
        height, width = image.shape[:2]
        for extra in extras:
            box = extra["box"]
            pixel_width, pixel_height = box["width"] * width, box["height"] * height
            extra.update(detectedFontSize=min(pixel_width, pixel_height), sourceIsVertical=pixel_height > pixel_width,
                         rotationDegrees=0)
        mask, boxes = effect_mask(image, matched + extras)
        blocks.extend(extras)
        return mask, boxes

    def add_sentence_punctuation(self, image, blocks: list[dict]) -> tuple:
        from sentence_punctuation import sentence_end_candidates, confirms_sentence_end
        from erase_supplemental_text import glyph_mask
        candidates = sentence_end_candidates(image, blocks)
        confirmed = []
        if candidates:
            self.ocr.load_model()
        for candidate in candidates:
            left, top, right, bottom = candidate.crop
            recognized = self.ocr.ocr_img(image[top:bottom, left:right])
            if confirms_sentence_end(candidate, recognized):
                confirmed.append(candidate.box)
        return glyph_mask(image, confirmed, bounded=True)

    @staticmethod
    def inpainting_regions(boxes: list) -> list["TextBlock"]:
        from ballontranslator.utils.textblock import TextBlock
        regions = []
        for left, top, right, bottom in boxes:
            block = TextBlock(xyxy=[left, top, right, bottom])
            block.set_lines_by_xywh([left, top, right - left, bottom - top])
            regions.append(block)
        return regions

    @staticmethod
    def inpainting_blocks(detected: list["TextBlock"], width: int, height: int) -> list["TextBlock"]:
        """Give LaMa padded crop polygons without changing the original OCR geometry.

        Ballons filters the erase mask using each block's line polygons, not its
        xyxy crop alone. Tight OCR polygons can cut off glyph tips at high resolution.
        These rectangles bound the existing ink mask; they do not fill or erase it.
        """
        boxes = []
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            pad = max(3, int(block._detected_font_size * .22))
            x1, y1, x2, y2 = max(0, x1 - pad), max(0, y1 - pad), min(width, x2 + pad), min(height, y2 + pad)
            boxes.append([x1, y1, x2, y2])
        return JapaneseEngine.inpainting_regions(boxes)

    def read_proposed_regions(self, image, regions: list[dict], backend: str = "manga") -> list[dict]:
        if len(regions) > 40:
            raise ValueError("Too many proposed regions")
        height, width = image.shape[:2]
        recognized = []
        for region in regions:
            box = region["box"]
            x, y, w, h = (box[key] for key in ("x", "y", "width", "height"))
            if not (0 <= x <= 1 and 0 <= y <= 1 and w > 0 and h > 0 and x + w <= 1.000001 and y + h <= 1.000001):
                raise ValueError("Invalid proposed rectangle")
            pad = max(4, int(min(w * width, h * height) * .05))
            x1, y1 = max(0, int(x * width) - pad), max(0, int(y * height) - pad)
            x2, y2 = min(width, int((x + w) * width) + pad), min(height, int((y + h) * height) + pad)
            reading = self.read_region(image[y1:y2, x1:x2], backend)
            verified = dict(region)
            verified.pop("recognitionAlternatives", None)
            verified.update(reading)
            # Retain the proposal's detector score, not an invented OCR probability.
            verified["confidence"] = region["confidence"]
            recognized.append(verified)
        return recognized

    def read_blocks(self, image, detected, backend: str) -> list[dict]:
        height, width = image.shape[:2]
        blocks = []
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            x1, y1, x2, y2 = max(0, x1), max(0, y1), min(width, x2), min(height, y2)
            if x2 <= x1 or y2 <= y1:
                raise ValueError("Detector returned an invalid text rectangle")
            reading = self.read_region(image[y1:y2, x1:x2], backend)
            blocks.append({"id": str(uuid.uuid4()), "box": {"x": x1 / width, "y": y1 / height,
                           "width": (x2 - x1) / width, "height": (y2 - y1) / height},
                           **reading, "translatedText": "",
                           "sourceIsVertical": bool(block.src_is_vertical),
                           "detectedFontSize": float(block._detected_font_size),
                           "rotationDegrees": float(block.angle)})
        return blocks

    def reread_existing(self, image, blocks: list[dict], backend: str) -> list[dict]:
        """An OCR upgrade rereads automatic source text, retaining stable IDs and user choices."""
        from balloon_lobes import source_rectangle
        from text_region_geometry import validate_box
        height, width = image.shape[:2]
        result = []
        for block in blocks:
            if block.get("keepsOriginal") is True or block.get("userDefinedOriginalText") is True or block.get("userDefinedBounds") is not None:
                result.append(block)
                continue
            validate_box(block["box"])
            left, top, right, bottom = source_rectangle(block["box"], width, height)
            updated = dict(block)
            updated.pop("recognitionAlternatives", None)
            updated.update(self.read_region(image[top:bottom, left:right], backend), translatedText="")
            result.append(updated)
        return result

    def prepare_title_mask(self, image, mask, detected) -> None:
        height, width = image.shape[:2]
        if width > 800 or width <= height:
            return
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            if y2 - y1 <= (x2 - x1) * 4:
                continue
            pad = int(block._detected_font_size)
            y1, y2 = max(0, y1 - pad), min(height, y2 + pad)
            block.xyxy = [x1, y1, x2, y2]
            mask[y1:y2, x1:x2] = 255

    def expand_outline_mask(self, image, mask, detected) -> None:
        """Erase white outlines with the ink, while leaving unrelated artwork outside the mask."""
        height, width = image.shape[:2]
        from balloon_geometry import white_background_ratio
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            box = {"x": x1 / width, "y": y1 / height, "width": (x2 - x1) / width, "height": (y2 - y1) / height}
            if white_background_ratio(image, box, block._detected_font_size) >= .7:
                continue
            pad = max(3, int(block._detected_font_size * .22))
            x1, y1, x2, y2 = max(0, x1 - pad), max(0, y1 - pad), min(width, x2 + pad), min(height, y2 + pad)
            local = mask[y1:y2, x1:x2]
            kernel = self.cv2.getStructuringElement(self.cv2.MORPH_ELLIPSE, (pad * 2 + 1, pad * 2 + 1))
            mask[y1:y2, x1:x2] = self.cv2.dilate(local, kernel)
            block.xyxy = [x1, y1, x2, y2]


def run() -> None:
    with contextlib.redirect_stdout(sys.stderr):
        engine = JapaneseEngine(Path(sys.argv[1]))
    for line in sys.stdin:
        try:
            with contextlib.redirect_stdout(sys.stderr):
                response = engine.process(json.loads(line))
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            response = {"error": f"{type(error).__name__}: {error}"}
        protocol_output.write(json.dumps(response, ensure_ascii=False) + "\n")
        protocol_output.flush()


if __name__ == "__main__":
    run()
