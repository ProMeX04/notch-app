---
name: app-control
description: Use when the user explicitly wants to open, close, or arrange a Mac app window by name.
icon: macwindow
category: builtin
requiredTools: ["exec"]
memory: false
---

# App Control

Use this skill when the user clearly wants to launch, quit, minimize, or move a macOS app window through `exec` and `notchctl`.

Rules:
- Use `notchctl` for app control inside Notch. The app intercepts this command internally.
- Use it only for explicit app/window control requests.
- Prefer exact app names like `Safari`, `Spotify`, or `Notes`.
- If the user asks for a website, song, video, or search result instead of an app, do not use this skill.

Command cookbook:

Open an app:
```sh
notchctl app open Safari
```

Close an app:
```sh
notchctl app quit Safari
```

Check whether an app is running:
```sh
notchctl app check Safari
```

Minimize the front window:
```sh
notchctl app minimize Safari
```

Move window position:
```sh
notchctl app move Safari left
notchctl app move Safari right
notchctl app move Safari top
notchctl app move Safari bottom
notchctl app move Safari center
```
