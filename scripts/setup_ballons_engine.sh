#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="${APP_SUPPORT:-"$HOME/Library/Application Support/Manga Lada"}"
SOURCE_DIR="${BALLONS_SOURCE_DIR:-"$APP_SUPPORT/BallonsTranslator-dev"}"
VENV_DIR="${BALLONS_VENV_DIR:-"$APP_SUPPORT/ballons-engine"}"
ZIP_PATH="${BALLONS_ZIP_PATH:-"$HOME/Downloads/BallonsTranslator-dev.zip"}"
REPO_URL="https://github.com/dmMaze/BallonsTranslator.git"

find_supported_python() {
  local candidate
  for candidate in python3.12 python3.11 python3.10 python3; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi
    if "$candidate" - <<'PY'
import sys
raise SystemExit(0 if (3, 8) <= sys.version_info < (3, 13) else 1)
PY
    then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

install_source_from_zip() {
  local tmp_dir source_root marker
  tmp_dir="$(mktemp -d)"
  ditto -x -k "$ZIP_PATH" "$tmp_dir"
  marker="$(find "$tmp_dir" -maxdepth 4 -type d -name ballontranslator -print -quit)"
  if [[ -z "$marker" ]]; then
    echo "BallonsTranslator source folder not found in $ZIP_PATH" >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  source_root="$(dirname "$marker")"
  mv "$source_root" "$SOURCE_DIR"
  rm -rf "$tmp_dir"
}

install_source() {
  if [[ -d "$SOURCE_DIR/ballontranslator" ]]; then
    return 0
  fi

  if [[ -e "$SOURCE_DIR" ]]; then
    echo "$SOURCE_DIR already exists but is not a BallonsTranslator source checkout." >&2
    return 1
  fi

  mkdir -p "$APP_SUPPORT"
  if [[ -f "$ZIP_PATH" ]]; then
    install_source_from_zip
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "git is required when $ZIP_PATH is not present." >&2
    return 1
  fi
  git clone --depth 1 --branch dev "$REPO_URL" "$SOURCE_DIR"
}

patch_headless_macos() {
  "$PYTHON_BIN" - "$SOURCE_DIR" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = source / "ui" / "mainwindow.py"
text = target.read_text(encoding="utf-8")
old = "if shared.ON_MACOS:\n            self.hideSystemTitleBar()"
new = "if shared.ON_MACOS and not shared.HEADLESS:\n            self.hideSystemTitleBar()"
if new in text:
    raise SystemExit(0)
if old not in text:
    raise SystemExit(f"Expected macOS titlebar hook not found in {target}")
target.write_text(text.replace(old, new), encoding="utf-8")
PY
}

PYTHON_BIN="$(find_supported_python)" || {
  echo "Python 3.8-3.12 is required for BallonsTranslator." >&2
  exit 1
}

install_source
patch_headless_macos

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install -e "$SOURCE_DIR"
"$VENV_DIR/bin/python" -m pip install -r "$SOURCE_DIR/requirements.txt"
"$VENV_DIR/bin/python" -m pip install \
  torch \
  torchvision \
  einops \
  "transformers==4.57.6" \
  jaconv \
  fugashi \
  unidic-lite

cat <<EOF
BallonsTranslator engine is ready.
Source: $SOURCE_DIR
Python: $VENV_DIR/bin/python

First translation can take longer while text detection and OCR models download.
EOF
