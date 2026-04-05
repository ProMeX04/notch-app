---
name: volume-control
description: Use when the user wants to get, set, mute, or unmute the system volume.
icon: speaker.wave.3
category: builtin
requiredTools: ["exec"]
memory: false
---

# Volume Control

Use this skill for macOS system volume actions through `exec` and AppleScript.

Rules:
- Use `get` to read the current output volume.
- Use `set` with an explicit numeric level for requested changes.
- Use `mute` and `unmute` only for system audio state, not app-specific playback.

Command cookbook:

Get current output volume:
```sh
osascript -e 'output volume of (get volume settings)'
```

Set output volume to 35:
```sh
osascript -e 'set volume output volume 35'
```

Mute output:
```sh
osascript -e 'set volume with output muted'
```

Unmute output:
```sh
osascript -e 'set volume without output muted'
```
