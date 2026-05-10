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
SWIFT_BUILD_ARGS=()
if [[ "${RELEASE:-}" == "1" ]]; then
    SWIFT_BUILD_ARGS=(-c release)
fi
swift build "${SWIFT_BUILD_ARGS[@]}"

# SwiftPM sinh Bundle.module tìm Notch_Notch.bundle tại Notch.app/Notch_Notch.bundle
# (Bundle.main.bundleURL = góc .app), trong khi bundle thật nằm ở Contents/Resources/.
# Vá accessor để ưu tiên Bundle.main.resourceURL — khớp layout .app đã ký; tránh lỗi
# "could not load resource bundle" khi cài từ zip/Homebrew.
while IFS= read -r accessor; do
    if grep -q 'Bundle.main.bundleURL.appendingPathComponent("Notch_Notch.bundle")' "$accessor" 2>/dev/null; then
        sed -i '' 's/Bundle\.main\.bundleURL\.appendingPathComponent("Notch_Notch\.bundle")/(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Notch_Notch.bundle")/g' "$accessor"
    fi
done < <(find "$ROOT_DIR/.build" -path '*/Notch.build/DerivedSources/resource_bundle_accessor.swift' 2>/dev/null || true)
swift build "${SWIFT_BUILD_ARGS[@]}"

BIN_DIR="$(swift build --show-bin-path "${SWIFT_BUILD_ARGS[@]}")"

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

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built app bundle at: $APP_DIR"
