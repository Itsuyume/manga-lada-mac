"""Adapter to the user's external BallonsTranslator installation. No model downloads."""
import json
import os
from pathlib import Path
import sys

import cv2
import numpy as np


def run() -> None:
    engine_root, clean_path, regions_path = map(Path, sys.argv[1:4])
    sys.path.insert(0, str(engine_root))
    os.chdir(engine_root)
    image = cv2.imread(str(clean_path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"Cannot decode image: {clean_path.name}")
    request = json.loads(regions_path.read_text(encoding="utf-8"))
    regions = request["regions"]
    source = cv2.imread(request["maskSource"], cv2.IMREAD_COLOR) if request.get("maskSource") else image
    if source is None or source.shape != image.shape:
        raise ValueError("Mask source and clean image dimensions differ")
    mask, boxes = glyph_mask(source, regions, bounded=request["bounded"])
    from flat_background import prepare_flat_backgrounds
    prepared, pending = prepare_flat_backgrounds(source, image, mask, boxes)
    from stroke_inpainting import prepare_thin_strokes
    prepared, pending = prepare_thin_strokes(prepared, pending)
    unresolved = [box for box in boxes if pending[box[1]:box[3], box[0]:box[2]].any()]
    result, method = prepared.copy(), "measured solid background"
    if unresolved:
        import torch
        from ballontranslator.modules.inpaint.inpaint_default import LamaLarge
        from ballontranslator.utils.textblock import TextBlock
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        painter = LamaLarge(device=device, inpaint_size=1536, precision="fp32")
        painter.check_need_inpaint = False
        result = painter.inpaint(prepared, pending.copy(), [TextBlock(xyxy=box) for box in unresolved])
        method = f"LaMa/{device}"
    if request["bounded"]:
        result[pending == 0] = prepared[pending == 0]
    restored = (mask > 0) & (pending == 0)
    result[restored] = prepared[restored]
    temporary = clean_path.with_name("supplemental-clean.partial.png")
    if not cv2.imwrite(str(temporary), result):
        raise OSError("Cannot save supplemental inpainting")
    os.replace(temporary, clean_path)
    print(f"Erased {len(regions)} supplemental regions using {method}")


def glyph_mask(image: np.ndarray, regions: list[dict], bounded: bool = False,
               minimum_component_area: int = 4) -> tuple[np.ndarray, list[list[int]]]:
    if not isinstance(minimum_component_area, int) or minimum_component_area < 1:
        raise ValueError("Minimum glyph component area must be a positive integer")
    height, width = image.shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)
    boxes = []
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    for region in regions:
        values = [region[key] for key in ("x", "y", "width", "height")]
        if not all(np.isfinite(values)) or min(values[:2]) < 0 or min(values[2:]) <= 0 or values[0] + values[2] > 1.000001 or values[1] + values[3] > 1.000001:
            raise ValueError("Invalid text-mask rectangle")
        seed_x, seed_y = region["x"] * width, region["y"] * height
        seed_w, seed_h = region["width"] * width, region["height"] * height
        if bounded:
            left, top, right, bottom = int(seed_x), int(seed_y), int(seed_x + seed_w), int(seed_y + seed_h)
            crop = gray[top:bottom, left:right]
            if crop.size == 0:
                raise ValueError("Text-mask rectangle is smaller than one pixel")
            outlined = outlined_glyph_mask(image[top:bottom, left:right])
            if outlined is not None:
                local = cv2.dilate(outlined, np.ones((7, 7), np.uint8))
                mask[top:bottom, left:right] = np.maximum(mask[top:bottom, left:right], local)
                boxes.append([left, top, right, bottom])
                continue
            # A nearby panel edge can cover half the crop perimeter. Measure
            # the selected area so that border ink cannot invert foreground.
            polarity = cv2.THRESH_BINARY if np.median(crop) < 127 else cv2.THRESH_BINARY_INV
            _, binary = cv2.threshold(crop, 0, 255, polarity | cv2.THRESH_OTSU)
            _, labels, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
            selected = [i for i in range(1, len(stats)) if stats[i, 4] >= minimum_component_area
                        and stats[i, 0] > 1 and stats[i, 1] > 1
                        and stats[i, 0] + stats[i, 2] < crop.shape[1] - 1
                        and stats[i, 1] + stats[i, 3] < crop.shape[0] - 1
                        and stats[i, 2] < crop.shape[1] * .85 and stats[i, 3] < crop.shape[0] * .9]
            if not selected:
                raise ValueError("No text strokes inside the selected area")
            local = np.isin(labels, selected).astype(np.uint8) * 255
            mask[top:bottom, left:right] = np.maximum(mask[top:bottom, left:right], cv2.dilate(local, np.ones((3, 3), np.uint8)))
            boxes.append([left, top, right, bottom])
            continue
        margin_x, margin_y = max(width * .04, seed_w * .6), max(height * .04, seed_h * .75)
        x1, y1 = max(0, int(seed_x - margin_x)), max(0, int(seed_y - margin_y))
        x2, y2 = min(width, int(seed_x + seed_w + margin_x)), min(height, int(seed_y + seed_h + margin_y))
        crop = gray[y1:y2, x1:x2]
        border = np.concatenate((crop[0], crop[-1], crop[:, 0], crop[:, -1]))
        polarity = cv2.THRESH_BINARY if np.median(border) < 127 else cv2.THRESH_BINARY_INV
        _, binary = cv2.threshold(crop, 0, 255, polarity | cv2.THRESH_OTSU)
        _, labels, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
        seed = (seed_x - x1, seed_y - y1, seed_x + seed_w - x1, seed_y + seed_h - y1)
        candidates = [i for i in range(1, len(stats)) if stats[i, 4] >= 4
                      and stats[i, 2] < crop.shape[1] * .85 and stats[i, 3] < crop.shape[0] * .9]
        primary = [i for i in candidates if stats[i, 4] >= 8 and overlaps(stats[i], seed)]
        if not primary:
            raise ValueError("No text strokes overlap the recognized sound effect")
        # Model boxes can cover only the body of a glyph or omit the last kana.
        # Recruit adjacent strokes at the same text scale, including dakuten.
        core = component_bounds(stats, primary)
        pad_x, pad_y = max(4, seed_h * .65), max(4, seed_h * .5)
        search = (core[0] - pad_x, core[1] - pad_y, core[2] + pad_x, core[3] + pad_y)
        selected = [i for i in candidates if overlaps(stats[i], search)]
        cluster = component_bounds(stats, selected)
        local = np.isin(labels, selected).astype(np.uint8) * 255
        local = cv2.dilate(local, np.ones((5, 5), np.uint8))
        mask[y1:y2, x1:x2] = np.maximum(mask[y1:y2, x1:x2], local)
        boxes.append([max(0, x1 + int(cluster[0])), max(0, y1 + int(cluster[1])),
                      min(width, x1 + int(cluster[2])), min(height, y1 + int(cluster[3]))])
    return mask, boxes


def outlined_glyph_mask(crop: np.ndarray, ink_mask: np.ndarray | None = None):
    """Recognize closed white outlines and include their dark ink, on varied backgrounds.

    Otsu alone can join the outline to a bright part of the artwork or erase only
    the dark fill. Require multiple compact outlines enclosing dark strokes;
    border-connected artwork and a mostly bright selected area do not qualify.
    """
    if ink_mask is not None and (ink_mask.shape != crop.shape[:2] or ink_mask.dtype != np.uint8):
        raise ValueError("Outline ink evidence does not match its source crop")
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    neutral = crop.max(axis=2).astype(np.int16) - crop.min(axis=2) <= 65
    bright = ((gray >= 200) & neutral).astype(np.uint8) * 255
    contours, _ = cv2.findContours(bright, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    mask = np.zeros_like(bright)
    outlined = 0
    height, width = gray.shape
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        if x <= 1 or y <= 1 or x + w >= width - 1 or y + h >= height - 1:
            continue
        if w >= width * .85 or h >= height * .9 or cv2.contourArea(contour) < 4:
            continue
        filled = np.zeros_like(bright)
        cv2.drawContours(filled, [contour], -1, 255, cv2.FILLED)
        inside = (filled > 0) & (bright == 0)
        dark = inside & (gray < 160)
        if dark.sum() < 4 or dark.sum() / max(1, inside.sum()) < .7:
            continue
        if ink_mask is not None and np.count_nonzero(dark & (ink_mask > 0)) < dark.sum() * .5:
            continue
        outlined += 1
        mask |= filled
    if outlined < 2 or np.count_nonzero(mask) > gray.size * .35:
        return None
    return mask


def complete_confirmed_glyph_mask(crop: np.ndarray, ink_mask: np.ndarray) -> np.ndarray:
    """Recover a glyph's faint edges only when existing ink confirms that component.

    Contrast alone cannot authorize a new glyph or a panel line. Components
    touching the search crop are excluded; the source balloon protection remains
    the final boundary before painting. Input pixels and evidence are read-only.
    """
    if ink_mask.dtype != np.uint8 or ink_mask.shape != crop.shape[:2]:
        raise ValueError("Confirmed glyph evidence does not match its source crop")
    completed = ink_mask.copy()
    if not ink_mask.any():
        return completed
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    background = np.median(gray)
    contrast = np.abs(gray.astype(float) - background)
    foreground = contrast >= 12
    _, labels, stats, _ = cv2.connectedComponentsWithStats(foreground.astype(np.uint8), 8)
    support = np.bincount(labels[ink_mask > 0], minlength=len(stats))
    height, width = gray.shape
    selected = [i for i in range(1, len(stats)) if stats[i, 4] >= 3
                and support[i] >= max(3, stats[i, 4] * .2)
                and stats[i, 0] > 0 and stats[i, 1] > 0
                and stats[i, 0] + stats[i, 2] < width and stats[i, 1] + stats[i, 3] < height
                and stats[i, 2] < width * .9 and stats[i, 3] < height * .9]
    core = np.isin(labels, selected).astype(np.uint8) * 255
    fringe = (cv2.dilate(core, np.ones((3, 3), np.uint8)) > 0) & (contrast >= 3)
    completed[fringe & (ink_mask == 0)] = 255
    return completed


def component_bounds(stats: np.ndarray, selected: list[int]) -> tuple[int, int, int, int]:
    return (min(stats[i, 0] for i in selected) - 4, min(stats[i, 1] for i in selected) - 4,
            max(stats[i, 0] + stats[i, 2] for i in selected) + 4,
            max(stats[i, 1] + stats[i, 3] for i in selected) + 4)


def overlaps(stat: np.ndarray, box: tuple[float, float, float, float]) -> bool:
    x, y, w, h = stat[:4]
    return min(x + w, box[2]) > max(x, box[0]) and min(y + h, box[3]) > max(y, box[1])


if __name__ == "__main__":
    run()
