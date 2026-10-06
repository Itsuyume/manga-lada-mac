"""Install optional manga-specific text strokes outside the app, with pinned local code."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.request import urlopen

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"))
from text_stroke_assets import (CODE_HASHES, CODE_ID, CODE_REVISION, MODEL_FILE, MODEL_ID,
                                MODEL_REVISION, prepare_text_strokes, verify_text_strokes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home()/"Library/Application Support/Manga Lada Claude/TextStrokes")
    parser.add_argument("--from-model", type=Path, help="Verified model snapshot; does not delete the source")
    parser.add_argument("--from-code", type=Path, help="Verified Hi-SAM source checkout")
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.exists():
        verify_text_strokes(destination)
        print(f"Already verified: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="text-strokes-install-", dir=destination.parent) as temporary:
        staged = Path(temporary)/"TextStrokes"
        staged.mkdir()
        model_source = args.from_model
        if model_source is None:
            model_source = Path(temporary)/"snapshot"
            subprocess.run([str(Path(sys.executable).parent/"hf"), "download", MODEL_ID,
                            MODEL_FILE, "README.md", "LICENSE", "--revision", MODEL_REVISION,
                            "--local-dir", str(model_source), "--quiet"], check=True,
                           env=os.environ | {"HF_HUB_DISABLE_IMPLICIT_TOKEN": "1"})
        for name in (MODEL_FILE, "README.md", "LICENSE"):
            shutil.copy2(model_source/name, staged/name)
        for name in list(CODE_HASHES) + ["LICENSE"]:
            target = staged/("Hi-SAM-LICENSE" if name == "LICENSE" else name)
            target.parent.mkdir(parents=True, exist_ok=True)
            if args.from_code is not None:
                shutil.copy2(args.from_code/name, target)
            else:
                with urlopen(f"https://raw.githubusercontent.com/{CODE_ID}/{CODE_REVISION}/{name}", timeout=60) as response:
                    target.write_bytes(response.read())
        prepare_text_strokes(staged)
        staged.rename(destination)
    print(f"Installed optional text strokes (1.35 GB, Apache-2.0): {destination}")


if __name__ == "__main__":
    main()
