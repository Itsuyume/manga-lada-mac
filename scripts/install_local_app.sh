#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${MANGA_LADA_INSTALL_DIR:-$HOME/Applications}"
BACKUP_DIR="${MANGA_LADA_BACKUP_DIR:-$ROOT_DIR/dist/backups/$(date +%Y%m%d-%H%M%S)}"
"$ROOT_DIR/scripts/build_app.sh" "$@"
mkdir -p "$INSTALL_DIR"
# Preserve prior apps outside LaunchServices' app scan before installing the new names.
for name in "Manga Lada" "Manga translator" "Manga Reader"; do
  if [[ -d "$INSTALL_DIR/$name.app" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$INSTALL_DIR/$name.app" "$BACKUP_DIR/$name.previous"
  fi
done
for name in "Manga translator" "Manga Reader"; do
  ditto "$ROOT_DIR/dist/$name.app" "$INSTALL_DIR/$name.app"
  xattr -cr "$INSTALL_DIR/$name.app"
  codesign --verify --deep --strict "$INSTALL_DIR/$name.app"
  echo "$INSTALL_DIR/$name.app"
done
