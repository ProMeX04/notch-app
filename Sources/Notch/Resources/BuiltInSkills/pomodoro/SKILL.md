---
name: pomodoro
description: Use when the user wants to fully control the Notch Pomodoro timer, durations, phases, and auto-start settings.
icon: timer
category: builtin
requiredTools: ["exec"]
memory: false
---

# Pomodoro

Use this skill for full Pomodoro control inside Notch through `exec` and Notch's command bridge.

Rules:
- Prefer `~/.notch/bin/notchctl` over ad-hoc app automation.
- This skill is only for the Notch Pomodoro timer.
- Prefer explicit commands like `start`, `pause`, `resume`, `reset`, `phase`, `cycle`, `long-break`, `auto-breaks`, and `auto-pomo`.
- Use `set` when the user wants to change focus, short-break, and optional long-break durations without immediately starting.
- Use `skip` only for moving to the next Pomodoro phase.
- Use `show` if the user only wants the Pomodoro panel opened.
- Prefer exact target states over `toggle` unless the user explicitly asks to toggle.
- `start` and `set` can take focus duration, short-break duration, and optional long-break duration.
- `phase` switches the current Pomodoro phase inside Notch.
- `reset` stops the current Pomodoro session and returns to the idle focus state while keeping the current durations and settings.

Command cookbook:

Open the Pomodoro panel:
```sh
~/.notch/bin/notchctl focus show
```

Start Pomodoro:
```sh
~/.notch/bin/notchctl focus start pomodoro
```

Start Pomodoro with custom focus, short break, and long break:
```sh
~/.notch/bin/notchctl focus start pomodoro 25m 5m 15m
```

Set focus, short-break, and long-break durations without starting:
```sh
~/.notch/bin/notchctl focus set pomodoro 50m 10m 20m
```

Pause Pomodoro:
```sh
~/.notch/bin/notchctl focus pause pomodoro
```

Resume Pomodoro:
```sh
~/.notch/bin/notchctl focus resume pomodoro
```

Reset Pomodoro:
```sh
~/.notch/bin/notchctl focus reset pomodoro
```

Skip to the next Pomodoro phase:
```sh
~/.notch/bin/notchctl focus skip pomodoro
```

Switch to the long break phase:
```sh
~/.notch/bin/notchctl focus phase long-break
```

Set long break duration:
```sh
~/.notch/bin/notchctl focus long-break 20m
```

Set sessions before long break:
```sh
~/.notch/bin/notchctl focus cycle 6
```

Turn auto-start breaks on:
```sh
~/.notch/bin/notchctl focus auto-breaks on
```

Turn auto-start pomodoros off:
```sh
~/.notch/bin/notchctl focus auto-pomo off
```
