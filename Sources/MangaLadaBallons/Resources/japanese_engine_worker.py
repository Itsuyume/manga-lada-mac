"""Local JSON-lines adapter. Models stay resident for the whole book."""
import contextlib
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
        self.detector = ComicTextDetector(device="cpu", detect_size=1280)
        self.ocr = MangaOCR(device=device)
        self.painter = LamaLarge(device=device, inpaint_size=1536, precision="fp32")
        # The library's white-background shortcut mistakes outlined text for empty balloons.
        self.painter.check_need_inpaint = False

    def process(self, request: dict) -> dict:
        began = time.monotonic()
        image = self.cv2.imread(request["source"], self.cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("Cannot decode source image")
        if request.get("regions") is not None:
            return {"blocks": self.read_proposed_regions(image, request["regions"])}
        height, width = image.shape[:2]
        mask, detected = self.detector.detect(image)
        self.prepare_title_mask(image, mask, detected)
        text_mask = mask.copy()
        blocks = request.get("blocks")
        if blocks is None:
            self.ocr.load_model()
            blocks = self.read_blocks(image, mask, detected)
        self.expand_outline_mask(image, mask, detected)
        paint_blocks = self.inpainting_blocks(detected, width, height)
        result = self.painter.inpaint(image, mask, paint_blocks, check_need_inpaint=False) if paint_blocks else image
        from balloon_geometry import BalloonGeometry, separate_shared_balloons
        from text_region_kind import classify_text_kind
        geometry = BalloonGeometry(image, text_mask=text_mask)
        for block in blocks:
            block["balloonShape"] = geometry.shape(block["box"], block["detectedFontSize"])
            kind = classify_text_kind(block)
            if kind is not None:
                block["textKind"] = kind
        separate_shared_balloons(blocks)
        destination = Path(request["destination"])
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name("recognized.partial.png")
        if not self.cv2.imwrite(str(temporary), result):
            raise OSError("Cannot save clean page")
        os.replace(temporary, destination)
        return {"blocks": blocks, "elapsed": time.monotonic() - began}

    @staticmethod
    def inpainting_blocks(detected: list["TextBlock"], width: int, height: int) -> list["TextBlock"]:
        """Give LaMa padded crop polygons without changing the original OCR geometry.

        Ballons filters the erase mask using each block's line polygons, not its
        xyxy crop alone. Tight OCR polygons can cut off glyph tips at high resolution.
        These rectangles bound the existing ink mask; they do not fill or erase it.
        """
        from ballontranslator.utils.textblock import TextBlock
        regions = []
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            pad = max(3, int(block._detected_font_size * .22))
            x1, y1, x2, y2 = max(0, x1 - pad), max(0, y1 - pad), min(width, x2 + pad), min(height, y2 + pad)
            region = TextBlock(xyxy=[x1, y1, x2, y2])
            region.set_lines_by_xywh([x1, y1, x2 - x1, y2 - y1])
            regions.append(region)
        return regions

    def read_proposed_regions(self, image, regions: list[dict]) -> list[dict]:
        if len(regions) > 40:
            raise ValueError("Too many proposed regions")
        self.ocr.load_model()
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
            text = self.ocr.ocr_img(image[y1:y2, x1:x2]).strip()
            if text:
                verified = dict(region)
                verified["originalText"] = text
                verified["confidence"] = .65
                recognized.append(verified)
        return recognized

    def read_blocks(self, image, mask, detected) -> list[dict]:
        height, width = image.shape[:2]
        blocks = []
        for block in detected:
            x1, y1, x2, y2 = map(int, block.xyxy)
            x1, y1, x2, y2 = max(0, x1), max(0, y1), min(width, x2), min(height, y2)
            if x2 <= x1 or y2 <= y1:
                raise ValueError("Detector returned an invalid text rectangle")
            text = self.ocr.ocr_img(image[y1:y2, x1:x2]).strip()
            if not text:
                raise ValueError("Manga OCR returned empty text for a detected region")
            blocks.append({"id": str(uuid.uuid4()), "box": {"x": x1 / width, "y": y1 / height,
                           "width": (x2 - x1) / width, "height": (y2 - y1) / height},
                           "originalText": text, "translatedText": "", "confidence": 1,
                           "sourceIsVertical": bool(block.src_is_vertical),
                           "detectedFontSize": float(block._detected_font_size),
                           "rotationDegrees": float(block.angle)})
        return blocks

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
