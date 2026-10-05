"""Install the optional noncommercial OCR-proposal model outside the app and repository."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"))
from manga_text_detector import MODEL_ID, MODEL_REVISION, MODEL_FILE, MODEL_LICENSE, verify_detector


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home()/"Library/Application Support/Manga Lada/TextDetector")
    parser.add_argument("--from-snapshot", type=Path, help="Pinned local snapshot containing weights and README.md")
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.exists():
        verify_detector(destination/MODEL_FILE)
        print(f"Already verified: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="text-detector-install-", dir=destination.parent) as temporary:
        staged = Path(temporary)/"TextDetector"
        staged.mkdir()
        if args.from_snapshot is None:
            hf = Path(sys.executable).parent/"hf"
            subprocess.run([str(hf), "download", MODEL_ID, MODEL_FILE, "README.md", "--revision", MODEL_REVISION,
                            "--local-dir", str(staged), "--quiet"], check=True,
                           env=os.environ | {"HF_HUB_DISABLE_IMPLICIT_TOKEN": "1"})
        else:
            for name in (MODEL_FILE, "README.md"):
                shutil.copy2(args.from_snapshot/name, staged/name)
        verify_detector(staged/MODEL_FILE)
        staged.rename(destination)
    print(f"Installed optional detector ({MODEL_LICENSE}): {destination}")


if __name__ == "__main__":
    main()
