#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build "$@" --explicit-target-dependency-import-check error
binary_directory=$(swift build "$@" --show-bin-path)
check_directory=$(mktemp -d "${TMPDIR:-/tmp}/manga-translation-state.XXXXXX")
trap 'rm -rf "$check_directory"' EXIT
for resource in "$binary_directory"/*.bundle; do
  [[ ! -d "$resource" ]] || ditto "$resource" "$check_directory/$(basename "$resource")"
done
objects=()
for module in MangaLadaCore MangaLadaImport MangaLadaRendering MangaLadaWorkflow MangaLadaVision MangaLadaBallons MangaLadaViewerUI; do
  if [[ -f "$binary_directory/$module.o" ]]; then
    objects+=("$binary_directory/$module.o")
  else
    objects+=("$binary_directory/$module.build/"*.o)
  fi
done
compiler_flags=(-parse-as-library -swift-version 6 -package-name MangaLadaMac)
while (($#)); do
  case "$1" in
    --sdk) compiler_flags+=(-sdk "$2"); shift 2 ;;
    --scratch-path) shift 2 ;;
    --build-system) shift 2 ;;
    *) echo "Unsupported check option: $1" >&2; exit 2 ;;
  esac
done
sources=()
for source in Sources/MangaLadaApp/*.swift; do
  [[ "$source" == */MangaLadaApp.swift ]] || sources+=("$source")
done
# Compile the real app state and views. Only cache/review storage is relocated;
# no processor, pipeline, UI-state or model implementation is replaced.
swiftc "${compiler_flags[@]}" \
  -I "$binary_directory" -I "$binary_directory/Modules" \
  "${sources[@]}" Sources/MangaLadaWorkflow/JapanesePageKeys.swift \
  Tests/MangaLadaAppTests/*.swift \
  "${objects[@]}" -o "$check_directory/checks"
"$check_directory/checks"
