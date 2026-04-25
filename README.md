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

The app exposes a local bridge at `http://127.0.0.1:44991`. The extension reads the current focus state and redirects matching tabs to an internal block page only while the app reports an active running focus phase.

## Portal

The web account and auth flow now live in [`portal/`](portal).
