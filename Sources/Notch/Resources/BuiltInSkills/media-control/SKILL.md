---
name: media-control
description: Use when the user wants to control playback, system volume, skip, shuffle, repeat, or favorite media.
icon: playpause
category: builtin
requiredTools: ["exec"]
memory: false
---

# Media Control

Use this skill for playback actions and macOS system volume actions on the user's Mac through `exec` and Notch's own command bridge.

Rules:
- Use it for play, pause, resume, next, previous, stop, skip, or volume (both system and app-specific).
- If the user is asking to open media in a browser instead of controlling playback, prefer the browser skill.
- Use `notchctl` for media control inside Notch. The app intercepts this command internally.
- `notchctl` routes into the running Notch app, which already uses its own media controller and MediaRemote integration.
- If no supported media app is running, say so clearly instead of guessing.
- Prefer explicit actions:
- Use `media play` for play or resume.
- Use `media pause` for pause.
- Use `media toggle` only when the user explicitly asks to toggle play/pause, or when the desired final state is unclear.
- For system volume, use the `notchctl volume` commands. Use `get` to read the current output volume, `set` with an explicit numeric level, and `mute`/`unmute` for system audio state.

Command cookbook:

## Playback

Play or resume:
```sh
notchctl media play
```

Pause:
```sh
notchctl media pause
```

Toggle only when needed:
```sh
notchctl media toggle
```

Next track:
```sh
notchctl media next
```

Previous track:
```sh
notchctl media previous
```

Skip forward 30 seconds:
```sh
notchctl media skip-forward 30
```

Skip backward 15 seconds:
```sh
notchctl media skip-backward 15
```

Stop:
```sh
notchctl media stop
```

Set app volume to 35:
```sh
notchctl media volume 35
```

Open the current media app:
```sh
notchctl media open
```

## System Volume

Get current output volume:
```sh
notchctl volume get
```

Set output volume to 35:
```sh
notchctl volume set 35
```

Mute output:
```sh
notchctl volume mute
```

Unmute output:
```sh
notchctl volume unmute
```

Use Notch commands directly because they are more stable than raw app-specific AppleScript.
