#!/usr/bin/env python3
"""Behavior checks for OCR kind hints using real contour detection, without models."""
from copy import deepcopy
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"))
import cv2
import numpy as np
from balloon_geometry import BalloonGeometry
from text_region_kind import classify_text_kind


def enclosed(color: int, rectangle: bool = True) -> tuple:
    image = np.full((640, 640, 3), 145, np.uint8)
    if rectangle:
        cv2.rectangle(image, (210, 190), (430, 450), (color,) * 3, -1)
    else:
        cv2.ellipse(image, (320, 320), (110, 140), 0, 0, 360, (color,) * 3, -1)
    box = {"x": 280 / 640, "y": 250 / 640, "width": 80 / 640, "height": 140 / 640}
    # Dense white lettering pushed the old OCR-crop average above its dark threshold.
    for y in range(250, 385, 10):
        cv2.line(image, (284, y), (355, y), (255 - color,) * 3, 3)
    block = {"box": box, "originalText": "三日後。", "translatedText": "사흘 뒤.",
             "balloonShape": BalloonGeometry(image).shape(box, 30)}
    assert block["balloonShape"] is not None, "Fixture lost its enclosing contour"
    return image, block


def check_kind(image, block, expected):
    pixels, original = image.copy(), deepcopy(block)
    actual = classify_text_kind(block)
    assert actual == expected, f"{block['originalText']}: expected {expected}, got {actual}"
    assert np.array_equal(image, pixels) and block == original, "Classification changed pixels, text, or geometry"


def run():
    for color in (20, 245):
        image, block = enclosed(color)
        check_kind(image, block, "caption")
        block["textKind"] = "dialogue"
        check_kind(image, block, "caption")
        for kind in ("dialogue", "caption", "soundEffect", "title"):
            block.update(textKind=kind, userDefinedTextKind=True)
            check_kind(image, block, kind)
        block.update(textKind="title", userDefinedTextKind=False)
        check_kind(image, block, "title")
    image, block = enclosed(20, rectangle=False)
    check_kind(image, block, None)  # Dark dialogue is not automatically narration.
    blank = np.zeros((1, 1, 3), np.uint8)
    for text in ("", "あっ", "アッ", "うん", "ナナ", "ママ", "ココ", "キキ", "ホテル", "ありがとう", "雨が降ってきた"):
        check_kind(blank, {"originalText": text, "balloonShape": None}, None)
    for text in ("ザアア", "ザーッ", "ゴゴゴ", "ドンドン", "カチッ", "ガチャン", "バタン", "ゴロゴロ", "ｻﾞｱｱ", "ザアア…"):
        effect = {"originalText": text, "balloonShape": None}
        check_kind(blank, effect, "soundEffect")
        effect.update(textKind="dialogue", userDefinedTextKind=True)
        check_kind(blank, effect, "dialogue")
    image, enclosed_sound = enclosed(245, rectangle=False)
    enclosed_sound["originalText"] = "ゴロゴロ"
    check_kind(image, enclosed_sound, None)  # Quoted or spoken sound words stay available to the translator.
    print("Text-kind checks passed: black/white captions, dense glyphs, dark dialogue, outside sound effects, ambiguous speech/names, explicit overrides, source preserved")


if __name__ == "__main__":
    run()
