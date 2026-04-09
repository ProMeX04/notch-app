#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist" 2>/dev/null || echo "0.1")"
DMG_NAME="Notch-${VERSION}.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/notch-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

cp -R "$ROOT_DIR/dist/Notch.app" "$STAGING/Notch.app"
ln -sf /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Notch ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

echo "DMG: $DMG_PATH"
