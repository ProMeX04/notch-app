---
name: app-control
description: Use when the user explicitly wants to open or close a Mac app by name.
icon: macwindow
category: builtin
requiredTools: ["exec"]
memory: false
---

# App Control

Use this skill when the user clearly wants to launch or quit a macOS app through `exec`.

Rules:
- Use it only for explicit open/close app requests.
- Prefer exact app names like `Safari`, `Spotify`, or `Notes`.
- If the user asks for a website, song, video, or search result instead of an app, do not use this skill.
- Use `open -a` to launch apps.
- Use AppleScript `quit` to close apps cleanly.

Command cookbook:

Open an app:
```sh
open -a "Safari"
```

Close an app:
```sh
osascript -e 'tell application "Safari" to quit'
```

Check whether an app is running:
```sh
pgrep -x "Safari" >/dev/null && echo "running" || echo "not running"
```
