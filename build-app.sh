#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Notch"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
SWIFT_BUILD_ARGS=()
if [[ "${RELEASE:-}" == "1" ]]; then
    SWIFT_BUILD_ARGS=(-c release)
fi
if [[ "${SCRATCH_PATH:-}" != "" ]]; then
    SWIFT_BUILD_ARGS+=(--scratch-path "$SCRATCH_PATH")
fi

# Mặc định KHÔNG clean — giữ incremental build cho lặp nhanh.
# Khi đổi dependency / build lỗi lạ: CLEAN=1 ./build-app.sh
if [[ "${CLEAN:-}" == "1" ]]; then
    swift package "${SWIFT_BUILD_ARGS[@]}" clean
fi
swift build "${SWIFT_BUILD_ARGS[@]}"

# SwiftPM sinh Bundle.module tự động nhưng không còn được dùng trực tiếp trong code để tránh crash
# và tránh phải build 2 lần gây mất thời gian (giúp giữ incremental build cực kỳ nhanh).

BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# LiveKit WebRTC (Gemini Live): binary expects @rpath/LiveKitWebRTC.framework; SwiftPM leaves it in BIN_DIR next to the executable (@loader_path).
if [[ -d "$BIN_DIR/LiveKitWebRTC.framework" ]]; then
    cp -R "$BIN_DIR/LiveKitWebRTC.framework" "$APP_DIR/Contents/MacOS/"
fi

cp -R "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_DIR/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

if [[ -f "$ROOT_DIR/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - --entitlements "$ROOT_DIR/Notch.entitlements" "$APP_DIR" >/dev/null

echo "Built app bundle at: $APP_DIR"
