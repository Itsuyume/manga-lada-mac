#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Manga Lada.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="${MANGA_LADA_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/$APP_NAME"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found: $SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP"
codesign --verify --deep --verbose=2 "$TARGET_APP"
echo "$TARGET_APP"
