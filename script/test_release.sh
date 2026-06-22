#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/OpenCodeConnectReleaseTests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

"$ROOT_DIR/script/release.sh" --output-dir "$TEMP_DIR"

ZIP_PATH="$TEMP_DIR/OpenCodeConnect.zip"
CHECKSUM_PATH="$TEMP_DIR/OpenCodeConnect.zip.sha256"
[[ -f "$ZIP_PATH" ]]
[[ -f "$CHECKSUM_PATH" ]]

(
  cd "$TEMP_DIR"
  /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
)

EXPANDED="$TEMP_DIR/expanded"
mkdir -p "$EXPANDED"
/usr/bin/ditto -x -k "$ZIP_PATH" "$EXPANDED"
/usr/bin/codesign --verify --deep --strict "$EXPANDED/OpenCodeConnect.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$EXPANDED/OpenCodeConnect.app/Contents/Info.plist")" == "true" ]]

echo "Release packaging behavior verified."
