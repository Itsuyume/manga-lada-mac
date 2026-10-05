"""Install the optional, pinned stroke model outside the app and repository."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"))
from lettering_strokes import MODEL_ID, MODEL_REVISION, MODEL_DIRECTORY, MODEL_FILE, verify_stroke_model


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home()/"Library/Application Support/Manga Lada/LetteringStrokes")
    parser.add_argument("--from-snapshot", type=Path, help="Pinned directory containing weights, README.md and LICENSE")
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.exists():
        verify_stroke_model(destination/MODEL_FILE)
        print(f"Already verified: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lettering-strokes-install-", dir=destination.parent) as temporary:
        staged = Path(temporary)/"LetteringStrokes"
        staged.mkdir()
        source = args.from_snapshot
        if source is None:
            hf = Path(sys.executable).parent/"hf"
            subprocess.run([str(hf), "download", MODEL_ID, *[f"{MODEL_DIRECTORY}/{name}" for name in (MODEL_FILE, "README.md", "LICENSE")],
                            "--revision", MODEL_REVISION, "--local-dir", str(Path(temporary)/"snapshot"), "--quiet"],
                           check=True, env=os.environ | {"HF_HUB_DISABLE_IMPLICIT_TOKEN": "1"})
            source = Path(temporary)/"snapshot"/MODEL_DIRECTORY
        for name in (MODEL_FILE, "README.md", "LICENSE"):
            shutil.copy2(source/name, staged/name)
        verify_stroke_model(staged/MODEL_FILE)
        staged.rename(destination)
    print(f"Installed optional stroke model (Apache-2.0): {destination}")


if __name__ == "__main__":
    main()
