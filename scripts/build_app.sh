#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${MANGA_LADA_BUILD_ROOT:-${TMPDIR:-/tmp}/manga-translator-build}"
cd "$ROOT_DIR"
swift build --scratch-path "$BUILD_ROOT" -c release "$@"
BIN_DIR="$(swift build --scratch-path "$BUILD_ROOT" -c release "$@" --show-bin-path)"

bundle_app() {
  local name="$1" executable="$2" identifier="$3" icon_variant="$4"
  local app_dir="$BUILD_ROOT/AppBundles/$name.app"
  rm -rf "$app_dir"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
  cp "$BIN_DIR/$executable" "$app_dir/Contents/MacOS/$executable"
  for resource in "$BIN_DIR"/*.bundle; do
    if [[ "$executable" == "MangaLada" && -d "$resource" ]]; then
      ditto "$resource" "$app_dir/Contents/Resources/$(basename "$resource")"
    fi
  done
  swift "$ROOT_DIR/scripts/make_icon.swift" "$app_dir/Contents/Resources/AppIcon.icns" "$icon_variant"
  cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleExecutable</key><string>$executable</string>
  <key>CFBundleIdentifier</key><string>$identifier</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDocumentTypes</key><array>
    <dict><key>CFBundleTypeName</key><string>Comic pages</string>
      <key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.image</string><string>com.adobe.pdf</string><string>public.folder</string></array>
    </dict>
    <dict><key>CFBundleTypeName</key><string>Comic archive</string>
      <key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array>
        <string>zip</string><string>cbz</string><string>7z</string><string>cb7</string><string>rar</string><string>cbr</string>
        <string>tar</string><string>tgz</string><string>gz</string><string>tbz</string><string>tbz2</string><string>bz2</string><string>txz</string><string>xz</string>
      </array>
    </dict>
  </array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.11</string>
  <key>CFBundleVersion</key><string>14</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
  chmod +x "$app_dir/Contents/MacOS/$executable"
  xattr -cr "$app_dir"
  codesign --force --deep --sign - "$app_dir"
  codesign --verify --deep --strict "$app_dir"
  mkdir -p "$ROOT_DIR/dist"
  rm -rf "$ROOT_DIR/dist/$name.app"
  ditto "$app_dir" "$ROOT_DIR/dist/$name.app"
  echo "$ROOT_DIR/dist/$name.app"
}

bundle_app "Manga translator" "MangaLada" "local.mangalada.mac" "translator"
bundle_app "Manga Reader" "MangaReader" "local.mangareader.mac" "reader"
