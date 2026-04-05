---
name: browser-control
description: Use when the user wants to open a web result, switch browser tabs, or read the current page.
icon: safari
category: builtin
requiredTools: ["exec"]
memory: false
---

# Browser Control

Use this skill for browser work through `exec`, `open`, and AppleScript.

Rules:
- For music, songs, albums, artists, or music videos without a direct URL, open a search in the default browser.
- For direct links, open the URL directly.
- Prefer simple browser actions: open a URL, open a search, read the front tab URL, or close/reload the front tab.
- Use AppleScript only when browser context really matters.

Command cookbook:

Open a direct URL:
```sh
open "https://example.com"
```

Open a web search:
```sh
open "https://duckduckgo.com/?q=lofi+hip+hop"
```

Read the current Safari tab URL:
```sh
osascript -e 'tell application "Safari" to return URL of current tab of front window'
```

Read the current Safari tab title:
```sh
osascript -e 'tell application "Safari" to return name of current tab of front window'
```

Read the current Chrome tab URL:
```sh
osascript -e 'tell application "Google Chrome" to return URL of active tab of front window'
```

Reload the current Safari tab:
```sh
osascript -e 'tell application "Safari" to tell current tab of front window to do JavaScript "location.reload()"'
```

Close the current Safari tab:
```sh
osascript -e 'tell application "Safari" to close current tab of front window'
```
