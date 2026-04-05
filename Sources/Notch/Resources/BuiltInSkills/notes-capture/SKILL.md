---
name: notes-capture
description: Use when the user wants to save a note or create a reminder.
icon: square.and.pencil
category: builtin
requiredTools: ["exec"]
memory: false
---

# Notes Capture

Use this skill to create notes and reminders quickly through `exec` and AppleScript.

Rules:
- Use Notes for notes and Reminders for reminders.
- Preserve the user's wording as much as possible.
- Ask for missing note details only when they matter.

Command cookbook:

Create a note in Notes:
```sh
osascript -e 'tell application "Notes" to make new note with properties {body:"Buy milk tomorrow"}'
```

Create a reminder in the default Reminders list:
```sh
osascript -e 'tell application "Reminders" to tell default account to tell default list to make new reminder with properties {name:"Buy milk tomorrow"}'
```
