"""Recover missed lettering using independent detection, bounded strokes and source OCR."""
from typing import Callable
import uuid
import cv2
import numpy as np
from balloon_candidates import BalloonCandidate, balloon_candidates
from lettering_regions import candidate_crop
from region_ocr import recognize_region
from text_detection import TextDetection, contact_crop_bounds, distinct_detections
from text_region_geometry import intersection_area, validate_bgr_image, validate_box


def recover_lettering(image: np.ndarray, blocks: list[dict],
                      detect: Callable[[np.ndarray], list[TextDetection]],
                      recognize: Callable[[np.ndarray], str], limit: int = 8,
                      segment: Callable[[np.ndarray, tuple[int, int, int, int]], list[np.ndarray]] | None = None
                      ) -> tuple[np.ndarray, list[dict]]:
    validate_bgr_image(image)
    if type(limit) is not int or not 0 <= limit <= 8:
        raise ValueError("Lettering recovery budget must be between zero and eight")
    height, width = image.shape[:2]
    mask = np.zeros((height, width), np.uint8)
    if not limit:
        return mask, []
    occupied = []
    for block in blocks:
        for box in [block['box']] + ([block['userDefinedBounds']] if block.get('userDefinedBounds') else []):
            validate_box(box)
            occupied.append(dict(x=box['x']*width, y=box['y']*height,
                                 width=box['width']*width, height=box['height']*height))
    proposals = distinct_detections(detect(image.copy()))
    if not proposals:
        return mask, []
    for proposal in proposals:
        if proposal.bounds[2] > width or proposal.bounds[3] > height:
            raise ValueError("Text detector returned a region outside the page")
    candidates = balloon_candidates(image, [], connected_lettering=True)
    extras = []
    attempted = 0
    for proposal in proposals:
        if attempted >= limit:
            break
        if proposal.score < .35:
            continue
        left, top, right, bottom = contact_crop_bounds(proposal, proposals, (width, height))
        crop_box = dict(x=left, y=top, width=right-left, height=bottom-top)
        if any(intersection_area(crop_box, box) > 0 for box in occupied):
            continue
        attempted += 1
        confirmed = enclosed_ink(candidates, proposal, (left, top, right, bottom))
        if confirmed is None:
            if segment is None:
                continue
            crop = image[top:bottom, left:right].copy()
            reading = recognize_region(crop, recognize, 'hayai')
            if reading.get('recognitionAlternatives') is not None:
                continue
            from lettering_strokes import confirmed_strokes
            px1, py1, px2, py2 = proposal.bounds
            masks = segment(crop.copy(), (px1-left, py1-top, px2-left, py2-top))
            ink = confirmed_strokes(crop, reading['originalText'], masks, recognize)
            if ink is None:
                continue
        else:
            candidate, ink = confirmed
            crop = candidate_crop(image, candidate, (left, top, right, bottom))
            reading = recognize_region(crop, recognize, 'hayai')
        extras.append(dict(id=str(uuid.uuid4()),
            box=dict(x=left/width, y=top/height, width=(right-left)/width, height=(bottom-top)/height),
            **reading, translatedText='', sourceIsVertical=bottom-top > right-left,
            detectedFontSize=float(min(right-left, bottom-top)), rotationDegrees=0))
        mask[top:bottom, left:right] |= ink
        occupied.append(crop_box)
    return mask, extras


def enclosed_ink(candidates: list[BalloonCandidate], proposal: TextDetection,
                 bounds: tuple[int, int, int, int]) -> tuple[BalloonCandidate, np.ndarray] | None:
    left, top, right, bottom = bounds
    px1, py1, px2, py2 = proposal.bounds
    for candidate in candidates:
        x1, y1, x2, y2 = candidate.bounds
        if not x1 <= px1 < px2 <= x2 or not y1 <= py1 < py2 <= y2:
            continue
        inside = candidate.interior[py1-y1:py2-y1, px1-x1:px2-x1]
        if np.count_nonzero(inside) < inside.size*.9:
            continue
        _, labels, stats, _ = cv2.connectedComponentsWithStats(candidate.ink, 8)
        selected = []
        for index, (x, y, w, h, amount) in enumerate(stats[1:], 1):
            if amount < 4 or not left <= x+x1 < x+x1+w <= right or not top <= y+y1 < y+y1+h <= bottom:
                continue  # A partial connected stroke cannot be erased or treated as a full character.
            in_proposal = labels[py1-y1:py2-y1, px1-x1:px2-x1] == index
            if np.count_nonzero(in_proposal) >= amount*.8:
                selected.append(index)
        if not selected:
            continue
        local = np.isin(labels, selected).astype(np.uint8)*255
        ix1, iy1, ix2, iy2 = max(left, x1), max(top, y1), min(right, x2), min(bottom, y2)
        visible = candidate.ink[iy1-y1:iy2-y1, ix1-x1:ix2-x1] > 0
        selected_visible = local[iy1-y1:iy2-y1, ix1-x1:ix2-x1] > 0
        if np.count_nonzero(selected_visible) < np.count_nonzero(visible)*.98:
            continue  # Do not read a full crop while erasing only some of its characters.
        if np.count_nonzero(local) < 16:
            continue
        local = cv2.dilate(local, np.ones((3, 3), np.uint8)) & candidate.interior
        ink = np.zeros((bottom-top, right-left), np.uint8)
        ink[iy1-top:iy2-top, ix1-left:ix2-left] = local[iy1-y1:iy2-y1, ix1-x1:ix2-x1]
        return candidate, ink
    return None
