---
name: media-control
description: Use when the user wants to control playback, volume, skip, shuffle, repeat, or favorite media.
icon: playpause
category: builtin
requiredTools: ["exec"]
memory: false
---

# Media Control

Use this skill for playback actions on the user's Mac through `exec` and Notch's own command bridge.

Rules:
- Use it for play, pause, resume, next, previous, stop, skip, or volume.
- If the user is asking to open media in a browser instead of controlling playback, prefer the browser skill.
- Prefer `~/.notch/bin/notchctl` over raw `osascript`.
- `notchctl` routes into the running Notch app, which already uses its own media controller and MediaRemote integration.
- If the command fails because Notch is not installed or available, only then fall back to `osascript`.
- If no supported media app is running, say so clearly instead of guessing.
- Prefer explicit actions:
- Use `media play` for play or resume.
- Use `media pause` for pause.
- Use `media toggle` only when the user explicitly asks to toggle play/pause, or when the desired final state is unclear.

Command cookbook:

Play or resume:
```sh
~/.notch/bin/notchctl media play
```

Pause:
```sh
~/.notch/bin/notchctl media pause
```

Toggle only when needed:
```sh
~/.notch/bin/notchctl media toggle
```

Next track:
```sh
~/.notch/bin/notchctl media next
```

Previous track:
```sh
~/.notch/bin/notchctl media previous
```

Skip forward 30 seconds:
```sh
~/.notch/bin/notchctl media skip-forward 30
```

Skip backward 15 seconds:
```sh
~/.notch/bin/notchctl media skip-backward 15
```

Stop:
```sh
~/.notch/bin/notchctl media stop
```

Set app volume to 35:
```sh
~/.notch/bin/notchctl media volume 35
```

Open the current media app:
```sh
~/.notch/bin/notchctl media open
```

Fallback only if `notchctl` is unavailable and you must control Apple Music directly:
```sh
osascript -e 'if application "Music" is running then tell application "Music" to next track'
```

Use Notch commands first because they are more stable than raw app-specific AppleScript.
