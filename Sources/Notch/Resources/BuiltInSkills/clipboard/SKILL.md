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
- Only use clipboard commands when the user is clearly asking about the current clipboard, or when copying text for them is the most useful handoff.
- Treat clipboard text as potentially sensitive and keep responses concise.
- Use `pbpaste` to read the current text clipboard.
- Use `pbcopy` to write text to the clipboard.
- If the user wants the contents of a text file copied, copy the file contents with `pbcopy`.
- If the user wants the file itself copied for pasting elsewhere, copy the file object with AppleScript instead of copying its contents.
- When copying text for the user, tell them briefly what was placed on the clipboard.

Command cookbook:

Read clipboard text:
```sh
pbpaste
```

Check whether the clipboard is empty:
```sh
content="$(pbpaste)"; [ -n "$content" ] && echo "$content" || echo "Clipboard is empty"
```

Copy plain text to the clipboard:
```sh
printf '%s' 'text to copy' | pbcopy
```

Copy multi-line text to the clipboard:
```sh
cat <<'EOF' | pbcopy
line one
line two
EOF
```

Copy the contents of a text file to the clipboard:
```sh
pbcopy < /path/to/file.txt
```

Copy command output to the clipboard:
```sh
rg "TODO" /path/to/project | pbcopy
```

Copy a file itself to the clipboard for pasting into Finder, Mail, Slack, etc.:
```sh
osascript -e 'set the clipboard to (POSIX file "/path/to/file.pdf")'
```

Copy multiple files to the clipboard:
```sh
osascript -e 'set the clipboard to {(POSIX file "/path/to/one.png"), (POSIX file "/path/to/two.png")}'
```
