"""Install the optional pinned recognition-only model outside the app/repository."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"Sources/MangaLadaBallons/Resources"))
from hayai_lettering import MODEL_ID, MODEL_REVISION, VISION_ID, VISION_REVISION, MODEL_HASHES
from hayai_lettering import prepare_local_model, verify_installation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path.home()/"Library/Application Support/Manga Lada Claude/LetteringOCR")
    parser.add_argument("--from-snapshot", type=Path, help="Verified local directory containing model/ and processor/")
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination.exists():
        verify_installation(destination)
        print(f"Already verified: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lettering-install-", dir=destination.parent) as temporary:
        staged = Path(temporary)/"LetteringOCR"
        staged.mkdir()
        if args.from_snapshot is not None:
            shutil.copytree(args.from_snapshot/"model", staged/"model", ignore=shutil.ignore_patterns(".cache"))
            shutil.copytree(args.from_snapshot/"processor", staged/"processor", ignore=shutil.ignore_patterns(".cache"))
        else:
            hf = Path(sys.executable).parent/"hf"
            environment = os.environ | {"HF_HUB_DISABLE_IMPLICIT_TOKEN": "1"}
            subprocess.run([str(hf), "download", MODEL_ID, *MODEL_HASHES, "README.md", "--revision", MODEL_REVISION,
                            "--local-dir", str(staged/"model"), "--quiet"], check=True, env=environment)
            subprocess.run([str(hf), "download", VISION_ID, "config.json", "preprocessor_config.json",
                            "--revision", VISION_REVISION, "--local-dir", str(staged/"processor"), "--quiet"],
                           check=True, env=environment)
        prepare_local_model(staged/"model", staged/"processor")
        verify_installation(staged)
        staged.rename(destination)
    print(f"Installed recognition-only OCR: {destination}")


if __name__ == "__main__":
    main()
