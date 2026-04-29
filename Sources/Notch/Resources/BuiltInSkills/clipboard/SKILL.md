---
name: clipboard
description: Use when the user asks you to read what is currently copied, or when you should place text on the clipboard so they can paste it elsewhere.
icon: doc.on.clipboard
category: builtin
requiredTools: ["exec"]
memory: false
---

# Clipboard

Use this skill when the user refers to copied text, or when you should put something onto the clipboard for them.

Rules:
- Use `notchctl` for clipboard operations inside Notch. The app intercepts this command internally.
- Only use clipboard commands when the user is clearly asking about the current clipboard, or when copying text for them is the most useful handoff.
- Treat clipboard text as potentially sensitive and keep responses concise.
- When copying text for the user, tell them briefly what was placed on the clipboard.
- Use `clipboard write` for normal "copy this" requests unless the user explicitly wants the file itself pasted into Finder, Mail, Slack, or another app as an attachment/file object.
- Use `clipboard copy-file` only for copying the file reference itself, not the file's text contents and not ordinary text for `Cmd+V`.
- Do not fall back to raw `pbcopy`, `pbpaste`, `osascript`, or Finder AppleScript for clipboard work.
- `clipboard copy-file` can take one or more file paths. Quote any path that contains spaces.

Command cookbook:

Read clipboard text:
```sh
notchctl clipboard read
```

Copy plain text to the clipboard:
```sh
notchctl clipboard write "text to copy"
```

Copy a file itself to the clipboard for pasting into Finder, Mail, Slack, etc.:
```sh
notchctl clipboard copy-file /path/to/file.pdf
```

Copy multiple files themselves to the clipboard:
```sh
notchctl clipboard copy-file "/path/to/First File.pdf" "/path/to/Second File.png"
```
