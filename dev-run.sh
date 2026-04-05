#!/bin/zsh
# Build nhanh (incremental) + mở app trong dist/ — không copy /Applications.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"
"$ROOT_DIR/build-app.sh"
open "$ROOT_DIR/dist/Notch.app"
