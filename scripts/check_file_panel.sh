#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Reuse built Core/Import objects, then compile the real dialog boundary unchanged.
swift build "$@" --explicit-target-dependency-import-check error
binary_directory=$(swift build "$@" --show-bin-path)
check_directory=$(mktemp -d "${TMPDIR:-/tmp}/manga-file-panel-checks.XXXXXX")
trap 'rm -rf "$check_directory"' EXIT
objects=()
for module in MangaLadaCore MangaLadaImport; do
  if [[ -f "$binary_directory/$module.o" ]]; then
    objects+=("$binary_directory/$module.o")
  else
    objects+=("$binary_directory/$module.build/"*.o)
  fi
done
compiler_flags=()
while (($#)); do
  case "$1" in
    --sdk) compiler_flags+=(-sdk "$2"); shift 2 ;;
    --scratch-path) shift 2 ;;
    *) echo "Unsupported check option: $1" >&2; exit 2 ;;
  esac
done
swiftc -parse-as-library -swift-version 6 "${compiler_flags[@]}" \
  -I "$binary_directory" -I "$binary_directory/Modules" \
  Sources/MangaLadaViewerUI/ComicOpenPanel.swift \
  Tests/MangaLadaFilePanelTests/ComicOpenPanelTests.swift \
  "${objects[@]}" -o "$check_directory/checks"
"$check_directory/checks"
