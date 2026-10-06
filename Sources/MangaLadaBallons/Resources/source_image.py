"""Page decoding shared by the resident worker and the bounded erase adapter."""
from pathlib import Path
import subprocess
import sys
import tempfile

import cv2

# macOS ImageIO reads HEIC/AVIF and other formats the viewer accepts but OpenCV cannot decode.
SIPS = "/usr/bin/sips"


def read_color_image(path):
    """Decode with OpenCV; only a file it cannot read is converted by the system `sips` tool.

    The source file is never modified, and the temporary PNG is removed after decoding.
    Returns None when no decoder can read the file, matching cv2.imread.
    """
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is not None or not Path(path).is_file() or not Path(SIPS).is_file():
        return image
    with tempfile.TemporaryDirectory(prefix="manga-lada-decode-") as directory:
        converted = Path(directory) / "page.png"
        result = subprocess.run([SIPS, "-s", "format", "png", str(path), "--out", str(converted)],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                timeout=120, check=False)
        if result.returncode != 0 or not converted.is_file():
            message = result.stderr.decode("utf-8", "replace").strip()
            print(f"System image conversion failed ({result.returncode}): {message}", file=sys.stderr)
            return None
        return cv2.imread(str(converted), cv2.IMREAD_COLOR)
