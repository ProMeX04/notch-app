# Notch

A lightweight notch utility for macOS focused on media controls and focus tools.

## Features

- Media controls in the notch
- Pomodoro focus controls with direct duration settings
- Gemini Live talk tools (no shell exec; no Chrome extension bridge)
- Lightweight menu bar app
- SwiftPM build, no Xcode project required

## Build

```bash
swift build
./build-app.sh
open dist/Notch.app
```

## Browser notes

Chrome extension, local WebSocket bridge, and website blocklists were **removed**.  
`browserControl` only opens URLs (or a DuckDuckGo search) in the **system default browser**.

## Portal

The web account and auth flow lives in [`portal/`](portal).
