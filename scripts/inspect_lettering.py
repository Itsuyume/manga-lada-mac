"""Run only candidate detection and Japanese OCR. Never translate, erase or reuse page caches."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"))
import cv2
from hayai_lettering import HayaiLetteringOCR, MODEL_ID, MODEL_REVISION
from lettering_regions import inspect_lettering_regions


def inspect(paths, model_directory, device, mode):
    reader = None
    def recognize(crop):
        nonlocal reader
        if reader is None:
            reader = HayaiLetteringOCR(model_directory, device)
        return reader(crop)
    results = []
    for path in paths:
        started = time.monotonic()
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        image = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError(f"Cannot decode input: {path.name}")
        regions = inspect_lettering_regions(image, recognize, mode)
        if hashlib.sha256(path.read_bytes()).hexdigest() != before:
            raise RuntimeError(f"Source changed during recognition: {path.name}")
        results.append(dict(input=path.name, sha256=before, regions=regions,
                            elapsedSeconds=round(time.monotonic()-started, 3)))
    return dict(model=MODEL_ID, revision=MODEL_REVISION, device=device, mode=mode,
                decision="view agreement; not a semantic accuracy guarantee", results=results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--model-directory", type=Path, default=Path.home()/"Library/Application Support/Manga Lada/LetteringOCR")
    parser.add_argument("--device", choices=("mps", "cpu"), default="mps")
    parser.add_argument("--mode", choices=("scan", "crop"), default="scan", help="crop: inputs already contain only lettering")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("Output already exists; choose a new report path")
    output = inspect(args.images, args.model_directory, args.device, args.mode)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(output, stream, ensure_ascii=False, indent=2)
    try:
        # Atomic publication without replacing a report created concurrently.
        os.link(temporary, args.output)
    finally:
        temporary.unlink()
    print(f"Recognition-only report: {args.output}")


if __name__ == "__main__":
    main()
