#!/bin/zsh
# Build Notch.app, copy to /Applications, quit any running instance, then launch.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notch"
DEST="/Applications/${APP_NAME}.app"

cd "$ROOT_DIR"
"$ROOT_DIR/build-app.sh"

(killall "$APP_NAME" 2>/dev/null) || true
sleep 1

rm -rf "$DEST"
cp -R "$ROOT_DIR/dist/${APP_NAME}.app" "$DEST"

open "$DEST"
