---
name: talk-control
description: Use when the user wants to control the Notch Talk session, microphone, captions, or screen sharing.
icon: mic.badge.plus
category: builtin
requiredTools: ["exec"]
memory: false
---

# Talk Control

Use this skill for Notch Talk and Gemini Live controls through `exec` and Notch's command bridge.

Rules:
- Prefer `~/.notch/bin/notchctl` over ad-hoc app automation.
- Use this skill for Talk session controls, microphone mute state, captions, and screen sharing.
- Prefer explicit commands like `mute`, `unmute`, `caption on`, `caption off`, `screen full`, and `screen stop`.
- Use `toggle` only when the user explicitly asks for a toggle or the target state is unclear.
- Use `screen region` or `screen window` only when the user is prepared to interact with the picker.
- Do not use this skill for image overlay display; that belongs to `image`.

Command cookbook:

Open the Talk panel:
```sh
~/.notch/bin/notchctl panel talk
```

Connect Talk:
```sh
~/.notch/bin/notchctl talk connect
```

Disconnect Talk:
```sh
~/.notch/bin/notchctl talk disconnect
```

Mute microphone:
```sh
~/.notch/bin/notchctl talk mute
```

Unmute microphone:
```sh
~/.notch/bin/notchctl talk unmute
```

Toggle microphone:
```sh
~/.notch/bin/notchctl talk mic-toggle
```

Turn captions on:
```sh
~/.notch/bin/notchctl caption on
```

Turn captions off:
```sh
~/.notch/bin/notchctl caption off
```

Share full screen:
```sh
~/.notch/bin/notchctl screen full
```

Share a selected region:
```sh
~/.notch/bin/notchctl screen region
```

Share a selected app window:
```sh
~/.notch/bin/notchctl screen window
```

Stop screen sharing:
```sh
~/.notch/bin/notchctl screen stop
```
