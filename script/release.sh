#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OpenCodeConnect"
BUNDLE_ID="com.avoidthekitchen.OpenCodeConnect"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist/release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { echo "--output-dir requires a path" >&2; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "usage: $0 [--output-dir PATH]" >&2
      exit 2
      ;;
  esac
done

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

swift build --package-path "$ROOT_DIR" --configuration release --product "$APP_NAME"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --configuration release --show-bin-path)/$APP_NAME"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE" "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --options runtime --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
(
  cd "$OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$APP_NAME.zip" >"$APP_NAME.zip.sha256"
)

echo "Created $ZIP_PATH"
echo "Created $CHECKSUM_PATH"
