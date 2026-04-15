# Notch

A lightweight notch utility for macOS focused on media controls and focus tools.

## Features

- Media controls in the notch
- Pomodoro focus controls and presets
- Lightweight menu bar app
- SwiftPM build, no Xcode project required

## Build

```bash
swift build
./build-app.sh
open dist/Notch.app
```

## Gemini Live Backend

Notch now supports a managed Gemini Live backend that issues ephemeral tokens so users do not need to paste a Gemini API key into the app.

See [server/README.md](server/README.md) for the FastAPI service, required environment variables, and local run instructions.
