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
- Use `notchctl` for Talk control inside Notch. The app intercepts this command internally.
- Use this skill for Talk session controls, microphone mute state, captions, and screen sharing.
- Prefer explicit commands like `mute`, `unmute`, `caption on`, `caption off`, `screen full`, and `screen stop`.
- Use `toggle` only when the user explicitly asks for a toggle or the target state is unclear.
- Use `screen region` or `screen window` only when the user is prepared to interact with the picker.

Command cookbook:

Open the Talk panel:
```sh
notchctl panel talk
```

Connect Talk:
```sh
notchctl talk connect
```

Disconnect Talk:
```sh
notchctl talk disconnect
```

Mute microphone:
```sh
notchctl talk mute
```

Unmute microphone:
```sh
notchctl talk unmute
```

Toggle microphone:
```sh
notchctl talk mic-toggle
```

Turn captions on:
```sh
notchctl caption on
```

Turn captions off:
```sh
notchctl caption off
```

Share full screen:
```sh
notchctl screen full
```

Share a selected region:
```sh
notchctl screen region
```

Share a selected app window:
```sh
notchctl screen window
```

Stop screen sharing:
```sh
notchctl screen stop
```
