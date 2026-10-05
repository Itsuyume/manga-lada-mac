"""Broken-border regressions: actual contour output, containment and side effects."""
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
import sys

sys.dont_write_bytecode = True
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"
sys.path.insert(0, str(resources))
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry
from balloon_lobes import detect_lobes, split_contour
from dotted_balloon import dotted_contours


@dataclass
class Detection:
    xyxy: list[int]
    lines: list
    _detected_font_size: float = 22
    src_is_vertical: bool = True


def dotted_ellipse(page, center, axes, scale, missing_arc=0):
    for angle in range(missing_arc, 360, 10):
        cv2.ellipse(page, tuple(round(v*scale) for v in center), tuple(round(v*scale) for v in axes),
                    0, angle, angle+3, (25,)*3, max(1, round(2*scale)))


def shape_pixels(shape, width, height):
    points = [(round(row['left']*width), round(row['y']*height)) for row in shape['rows']]
    points += [(round(row['right']*width), round(row['y']*height)) for row in reversed(shape['rows'])]
    mask = np.zeros((height, width), np.uint8)
    cv2.fillPoly(mask, [np.asarray(points, np.int32)], 1)
    return mask


def check_dotted_scales():
    for scale in (.5, 1, 2, 4):
        width, height = round(800*scale), round(700*scale)
        source = np.full((height, width, 3), 245, np.uint8)
        dotted_ellipse(source, (400, 320), (75, 110), scale)
        ink = np.zeros((height, width), np.uint8)
        # A detection mask often covers the spaces between characters, too.
        cv2.rectangle(ink, (round(392*scale), round(255*scale)), (round(409*scale), round(385*scale)), 255, -1)
        for top in range(260, 380, 24):
            cv2.rectangle(source, (round(397*scale), round(top*scale)),
                          (round(404*scale), round((top+10)*scale)), (25,)*3, -1)
        box = dict(x=391/800, y=255/700, width=20/800, height=132/700)
        original, mask_before = source.copy(), ink.copy()
        shape = BalloonGeometry(source, ink).shape(box, 22*scale)
        assert shape is not None, f"Dotted white balloon lost at scale {scale}"
        pixels = shape_pixels(shape, width, height)
        reference = np.zeros_like(ink)
        cv2.ellipse(reference, (round(400*scale), round(320*scale)), (round(75*scale), round(110*scale)), 0, 0, 360, 1, -1)
        assert np.count_nonzero(pixels & reference) > np.count_nonzero(reference)*.8, "Approximation discarded readable space"
        assert np.count_nonzero(pixels & (1-reference)) < np.count_nonzero(pixels)*.015, "Approximation escaped the real border"
        assert np.array_equal(source, original) and np.array_equal(ink, mask_before), "Gap closure modified source or detector mask"


def check_no_invented_enclosure():
    box = dict(x=391/800, y=255/700, width=20/800, height=132/700)
    rectangle = (391, 255, 20, 132)
    for shade in (0, 145, 245):
        blank = np.full((700, 800, 3), shade, np.uint8)
        assert BalloonGeometry(blank).shape(box, 22) is None
        assert not dotted_contours(blank, None, rectangle, 22), "Blank paper became a dotted balloon"
    open_border = np.full((700, 800, 3), 245, np.uint8)
    dotted_ellipse(open_border, (400, 320), (75, 110), 1, missing_arc=70)
    assert BalloonGeometry(open_border).shape(box, 22) is None, "A long missing arc was invented"
    clipped = np.full_like(open_border, 245)
    dotted_ellipse(clipped, (400, 10), (75, 110), 1)
    assert not dotted_contours(clipped, None, (391, 5, 20, 60), 22), "Crop edge closed an unobserved boundary"
    for size in (0, -1, float('nan'), float('inf')):
        assert not dotted_contours(open_border, None, rectangle, size)
    # A large illustrated panel must not become writable just because its border is dotted.
    illustrated = np.full_like(open_border, 245)
    dotted_ellipse(illustrated, (400, 320), (75, 110), 1)
    cv2.rectangle(illustrated, (340, 240), (385, 400), (25,)*3, -1)
    shape = BalloonGeometry(illustrated).shape(box, 22)
    if shape is not None:
        assert not shape_pixels(shape,800,700)[240:401,340:386].any(), "Approximation placed text on the illustration"


def check_adjacent_independent_balloons():
    page = np.full((700, 800, 3), 245, np.uint8)
    for x in (325, 490):
        dotted_ellipse(page, (x, 320), (75, 110), 1)
    geometry = BalloonGeometry(page)
    shapes = [geometry.shape(dict(x=(x-10)/800, y=255/700, width=20/800, height=132/700), 22) for x in (325, 490)]
    assert all(shapes), "Adjacent independent dotted balloons disappeared"
    first, second = [shape_pixels(shape, 800, 700) for shape in shapes]
    assert not np.any(first & second), "Gap closure joined two independent balloons"


def check_similar_color_outside_border():
    page = np.full((700,800,3),245,np.uint8)
    cv2.ellipse(page,(400,320),(75,110),0,0,360,(245,234,215),-1)
    cv2.rectangle(page,(390,260),(500,410),(245,234,215),-1)
    dotted_ellipse(page,(400,320),(75,110),1)
    mask = np.zeros(page.shape[:2],np.uint8)
    cv2.rectangle(mask,(392,255),(409,385),255,-1)
    for top in range(260,380,24):
        cv2.rectangle(page,(397,top),(404,top+10),(25,)*3,-1)
    before = page.copy()
    shape = BalloonGeometry(page,mask).shape(dict(x=391/800,y=255/700,width=20/800,height=132/700),22)
    assert shape is not None, "Observed dotted enclosure disappeared near similar-coloured artwork"
    assert max(row['right'] for row in shape['rows'])*800 <= 476, "Similar colour outside the dotted border became writable"
    assert np.array_equal(page,before), "Dotted colour comparison changed the source"


def check_existing_detector_columns():
    page = np.full((800, 800, 3), 145, np.uint8)
    balloon = np.zeros(page.shape[:2], np.uint8)
    cv2.ellipse(balloon, (315, 360), (65, 100), 0, 0, 360, 255, -1)
    cv2.ellipse(balloon, (390, 290), (28, 55), 0, 0, 360, 255, -1)
    page[balloon > 0] = (241, 238, 224)
    ink = np.zeros_like(balloon)
    blocks = []
    for x, y, width, height in [(383, 255, 14, 65), (307, 315, 15, 115)]:
        line = [[x,y], [x+width,y], [x+width,y+height], [x,y+height]]
        cv2.fillPoly(ink, [np.array(line)], 255)
        cv2.line(page, (x+6,y+8), (x+6,y+height-8), (25,)*3, 2)
        blocks.append(Detection([x,y,x+width,y+height], [line], 18))
    original, mask_before, before = page.copy(), ink.copy(), deepcopy(blocks)
    result = detect_lobes(page, ink, blocks)
    assert result.blocks == before and not result.replaced, "Existing OCR IDs/columns changed"
    assert len(result.shapes) == 2, "Separately detected columns never received physical lobes"
    small, large = [result.shapes[tuple(block.xyxy)] for block in blocks]
    assert small['bounds']['height'] < large['bounds']['height']*.75, "Small balloon claimed the long balloon's bottom"
    assert not np.any(shape_pixels(small,800,800) & shape_pixels(large,800,800)), "Physical lobes overlap"
    assert np.array_equal(page,original) and np.array_equal(ink,mask_before) and blocks == before


def check_column_padding_and_crossing():
    balloon = np.zeros((300, 250), np.uint8)
    cv2.ellipse(balloon, (90, 170), (65, 100), 0, 0, 360, 255, -1)
    cv2.ellipse(balloon, (165, 100), (28, 55), 0, 0, 360, 255, -1)
    lines = np.array([[[135,60],[190,60],[190,165],[135,165]],
                      [[65,125],[80,125],[80,225],[65,225]]])
    glyphs = np.zeros_like(balloon)
    cv2.rectangle(glyphs,(158,65),(172,130),255,-1)
    cv2.fillPoly(glyphs,[lines[1]],255)
    original = glyphs.copy()
    assert not split_contour(balloon,lines,18), "Oversized boxes without text evidence were guessed"
    assert len(split_contour(balloon,lines,18,glyphs)) == 2, "Blank detector padding blocked a valid whole-text cut"
    assert np.array_equal(glyphs, original), "Column assignment changed the detector mask"
    cv2.rectangle(glyphs,(135,85),(163,155),255,-1)
    assert not split_contour(balloon,lines,18,glyphs), "Cut crossed detected text spanning the neck"
    assert not split_contour(balloon,lines,18,np.zeros_like(glyphs)), "An empty text mask invented ownership"


check_no_invented_enclosure()
check_adjacent_independent_balloons()
check_similar_color_outside_border()
check_dotted_scales()
check_existing_detector_columns()
check_column_padding_and_crossing()
print('Dotted balloon checks passed: bounded gap closure, scale/area containment, open/edge/art rejection, separate lobes and source preservation')
