#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_directory=$(mktemp -d "${TMPDIR:-/tmp}/manga-viewer-checks.XXXXXX")
trap 'rm -rf "$check_directory"' EXIT
# Compile the production image boundary unchanged; no test-only public API or mocks.
swiftc -parse-as-library -swift-version 6 "$@" \
  Sources/MangaLadaViewerUI/PageImageLoader.swift \
  Sources/MangaLadaViewerUI/PageImageState.swift \
  Tests/MangaLadaViewerUITests/PageImageTests.swift \
  -o "$check_directory/checks"
"$check_directory/checks"
