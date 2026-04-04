#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notch"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
# Mặc định KHÔNG clean — giữ incremental build cho lặp nhanh.
# Khi đổi dependency / build lỗi lạ: CLEAN=1 ./build-app.sh
if [[ "${CLEAN:-}" == "1" ]]; then
    swift package clean
fi
swift build

BIN_DIR="$(swift build --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# LiveKit WebRTC (Gemini Live): binary expects @rpath/LiveKitWebRTC.framework; SwiftPM leaves it in BIN_DIR next to the executable (@loader_path).
if [[ -d "$BIN_DIR/LiveKitWebRTC.framework" ]]; then
    cp -R "$BIN_DIR/LiveKitWebRTC.framework" "$APP_DIR/Contents/MacOS/"
fi

# SwiftPM's generated Bundle.module accessor looks for the resource bundle at the app root.
cp -R "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_DIR/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

if [[ -f "$ROOT_DIR/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built app bundle at: $APP_DIR"
