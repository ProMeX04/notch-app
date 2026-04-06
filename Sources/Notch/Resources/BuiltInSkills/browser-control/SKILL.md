---
name: browser-control
description: Use when the user wants to play music via DuckDuckGo Lucky (first result in the default browser), or to open links, switch tabs, or read the current page.
icon: safari
category: builtin
requiredTools: ["exec"]
memory: false
---

# Browser Control

Use this skill when the user wants to **play music** or open a **top search result** in the **default browser** using **DuckDuckGo Lucky** (`!ducky`), or for other browser work through `exec`, `open`, and AppleScript.

## Default browser + DuckDuckGo Lucky for music

- **`open "https://…"`** always uses the user’s **default browser** (System Settings → Desktop & Dock → Default web browser).
- **DuckDuckGo Lucky** (`!ducky`): build `https://duckduckgo.com/?q=!ducky+<query>` (URL-encode spaces as `+` or `%20`) and run `open` on it via **`exec`**. The **first** search result opens in **one step**—use this to **play a song**, open a video, or land on the right page when the user has no exact link.
- For media keys / Now Playing, use **`exec`** with `osascript` or shell helpers as in the cookbook—not dedicated app tools.

Rules:
- **Play music / song / album / artist:** run **`exec`** with `open` and a Lucky URL (see cookbook), or `open "https://duckduckgo.com/?q=!ducky+…"`—DuckDuckGo Lucky opens the first hit in the default browser.
- **Direct link known:** `action=open` with `url` (or `open "https://…"` from shell).
- Prefer simple actions: Lucky query, open URL, read front tab, close/reload tab.
- Use AppleScript/JXA only when you need a named browser or extra control.

Command cookbook:

Open a URL in the **default browser**:

```sh
open "https://example.com"
```

Open the **top DuckDuckGo result** for a query—good for **music**:

```sh
open "https://duckduckgo.com/?q=!ducky+taylor+swift+anti-hero+official+audio"
```

Safari-only examples (when you must address Safari by name):

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
