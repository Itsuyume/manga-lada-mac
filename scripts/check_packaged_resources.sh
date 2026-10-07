#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/manga-resource-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc "$ROOT_DIR/Sources/MangaLadaCore/PackageResourceBundle.swift" \
  "$ROOT_DIR/scripts/check_packaged_resources.swift" -o "$CHECK_DIR/check"
"$CHECK_DIR/check" "$@"
