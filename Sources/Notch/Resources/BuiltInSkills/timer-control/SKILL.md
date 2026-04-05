---
name: timer-control
description: Use when the user wants to start, pause, resume, reset, or skip a Notch timer.
icon: timer
category: builtin
requiredTools: ["exec"]
memory: false
---

# Timer Control

Use this skill for Pomodoro, Countdown, and Stopwatch actions inside Notch through `exec` and Notch's command bridge.

Rules:
- Prefer `~/.notch/bin/notchctl` over old timer tools.
- Choose the correct timer:
- `pomodoro` -> `pomodoro`
- `countdown` -> `countdown`
- `stopwatch` -> `counter`
- Use explicit actions like `start`, `pause`, `resume`, and `reset`.
- Use `set` when the user wants to change durations without immediately starting.
- Use `skip` only for pomodoro phase changes.
- Use `show` first if the user wants to open the focus panel without changing state.
- Do not use this skill for calendar reminders or alarms outside the Notch timers.
- Durations are now supported through the command bridge:
- Pomodoro: `start` or `set` can take `focus-duration` and optional `break-duration`
- Countdown: `start` or `set` can take one duration
- Stopwatch does not use durations

Command cookbook:

Open focus panel:
```sh
~/.notch/bin/notchctl focus show
```

Start Pomodoro:
```sh
~/.notch/bin/notchctl focus start pomodoro
```

Start Pomodoro with custom focus and break:
```sh
~/.notch/bin/notchctl focus start pomodoro 25m 5m
```

Set Pomodoro durations without starting:
```sh
~/.notch/bin/notchctl focus set pomodoro 50m 10m
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

Skip Pomodoro phase:
```sh
~/.notch/bin/notchctl focus skip pomodoro
```

Start Countdown:
```sh
~/.notch/bin/notchctl focus start countdown
```

Start Countdown with custom duration:
```sh
~/.notch/bin/notchctl focus start countdown 10m
```

Set Countdown duration without starting:
```sh
~/.notch/bin/notchctl focus set countdown 45m
```

Reset Countdown:
```sh
~/.notch/bin/notchctl focus reset countdown
```

Start Stopwatch:
```sh
~/.notch/bin/notchctl focus start counter
```

Pause Stopwatch:
```sh
~/.notch/bin/notchctl focus pause counter
```

Reset Stopwatch:
```sh
~/.notch/bin/notchctl focus reset counter
```
