# Notch

A lightweight notch utility for macOS focused on media controls and focus tools.

## Features

- Media controls in the notch
- Pomodoro focus controls with direct duration settings
- Chrome extension bridge for blocking distracting websites during focus sessions
- Lightweight menu bar app
- SwiftPM build, no Xcode project required

## Build

```bash
swift build
./build-app.sh
open dist/Notch.app
```

## Chrome Focus Blocker

The repo includes a Chrome extension in [`chrome-extension/notch-focus-blocker`](./chrome-extension/notch-focus-blocker).

1. Build and run the macOS app.
2. Open the app Settings, then go to the Focus tab.
3. Add one blocked domain per line in `Blocked Websites`.
4. In Chrome, open `chrome://extensions`, enable Developer mode, then choose `Load unpacked`.
5. Select the `chrome-extension/notch-focus-blocker` folder.

The app exposes a local WebSocket bridge at `ws://127.0.0.1:44991/v1/ws`. The extension keeps one offscreen WebSocket session open, receives pushed focus state changes, and sends browser command results over the same channel. HTTP is only used for the WebSocket upgrade and optional `/v1/health` diagnostics, not as a state or command fallback.

## Portal

The web account and auth flow now live in [`portal/`](portal).
