#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

"$ROOT_DIR/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist" 2>/dev/null || echo "0.1")"
DMG_NAME="Notch-${VERSION}.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"

"$ROOT_DIR/../Configuration/dmg/create_dmg.sh" \
  "$ROOT_DIR/dist/Notch.app" \
  "$DMG_PATH" \
  "Notch"

echo "DMG: $DMG_PATH"
