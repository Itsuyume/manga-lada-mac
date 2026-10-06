#!/usr/bin/env python3
"""Page decoding checks; a real subprocess stands in for the macOS `sips` converter."""
from pathlib import Path
import sys
import tempfile

import cv2
import numpy as np

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources/MangaLadaBallons/Resources"))
import source_image
from source_image import read_color_image

# Accepts the `sips -s format png SOURCE --out TARGET` contract. A source carrying a 16-byte
# prefix ahead of PNG data (unreadable by OpenCV) is converted; anything else fails.
CONVERTER = """#!{python}
import sys
from pathlib import Path
source, target = Path(sys.argv[4]), Path(sys.argv[6])
data = source.read_bytes()
if sys.argv[1:4] != ["-s", "format", "png"] or sys.argv[5] != "--out" or not data.startswith(b"NOT-AN-OPENCV-IM"):
    sys.stderr.write("unsupported image")
    sys.exit(3)
target.write_bytes(data[16:])
"""


def run():
    with tempfile.TemporaryDirectory() as root:
        root = Path(root)
        page = np.zeros((40, 30, 3), np.uint8)
        page[5:20, 3:9] = (10, 120, 250)
        ok, encoded = cv2.imencode(".png", page)
        assert ok
        plain = root / "page.png"
        plain.write_bytes(encoded.tobytes())
        wrapped = root / "page.heic"
        wrapped.write_bytes(b"NOT-AN-OPENCV-IM" + encoded.tobytes())
        garbage = root / "broken.heic"
        garbage.write_bytes(b"\x00\x01broken")
        converter = root / "sips"
        converter.write_text(CONVERTER.format(python=sys.executable))
        converter.chmod(0o755)
        before = {path: path.read_bytes() for path in (plain, wrapped, garbage)}

        source_image.SIPS = str(root / "missing-sips")
        assert np.array_equal(read_color_image(plain), page), "OpenCV-readable pages changed"
        assert read_color_image(wrapped) is None, "Undecodable page was accepted without a converter"
        assert read_color_image(root / "missing.png") is None, "A missing page produced an image"

        source_image.SIPS = str(converter)
        assert np.array_equal(read_color_image(str(plain)), page), "String paths decode differently"
        assert np.array_equal(read_color_image(wrapped), page), "Converted pixels differ from the source"
        assert read_color_image(garbage) is None, "A failed conversion produced an image"
        assert read_color_image(root) is None, "A directory was sent to the converter"
        assert all(path.read_bytes() == data for path, data in before.items()), "Decoding modified a source file"
        assert sorted(path.name for path in root.iterdir()) == sorted(["page.png", "page.heic", "broken.heic", "sips"]), \
            "Conversion left temporary files beside the source"
    print("Source image checks passed: OpenCV pages unchanged, system conversion fallback, missing/failed/directory inputs, source and temporary file preservation")


if __name__ == "__main__":
    run()
