---
name: notes-capture
description: Use when the user wants to save a note.
icon: square.and.pencil
category: builtin
requiredTools: ["exec"]
memory: false
---

# Notes Capture

Use this skill to create notes quickly through `exec` and `notchctl`.

Rules:
- Use `notchctl` for Notes capture inside Notch. The app intercepts this command internally.
- Use Notes app for saving notes.
- Preserve the user's wording as much as possible.
- Ask for missing note details only when they matter.
- For reminders or scheduling, use the calendar tool instead.

Command cookbook:

Create a note in Notes:
```sh
notchctl notes create "Buy milk tomorrow"
```
