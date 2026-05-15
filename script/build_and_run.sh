#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Notch"
BUNDLE_ID="dev.notch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
BUILD_SCRIPT="$ROOT_DIR/build-app.sh"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  "$BUILD_SCRIPT"

  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: expected app bundle at $APP_BUNDLE" >&2
    exit 1
  fi

  if [[ ! -x "$APP_BINARY" ]]; then
    echo "error: expected executable at $APP_BINARY" >&2
    exit 1
  fi
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

find_pid() {
  pgrep -x "$APP_NAME" | head -n 1
}

stop_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    open_app
    sleep 2
    PID="$(find_pid)"
    if [[ -z "$PID" ]]; then
      echo "error: $APP_NAME did not start, cannot attach lldb" >&2
      exit 1
    fi
    exec lldb -p "$PID"
    ;;
  --logs|logs)
    open_app
    exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    PID="$(find_pid)"
    if [[ -z "$PID" ]]; then
      echo "error: $APP_NAME did not start" >&2
      exit 1
    fi
    echo "$APP_NAME is running with pid $PID"
    ;;
  *)
    usage
    exit 2
    ;;
esac
