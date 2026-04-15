---
name: browser-control
description: Use when the user wants to play music via DuckDuckGo Lucky (first result in the default browser), or to open links, switch tabs, or read the current page URL, title, or visible content in Edge, Safari, or another browser.
icon: safari
category: builtin
requiredTools: ["exec"]
memory: false
---

# Browser Control

Use this skill when the user wants to **play music** or open a **top search result** in the **default browser** using **DuckDuckGo Lucky** (`!ducky`), or for other browser work through `exec`, `open`, and AppleScript. This skill also covers reading the **current tab URL**, **title**, **selected text**, and **visible page content**, especially in **Microsoft Edge**.

## Default browser + DuckDuckGo Lucky for music

- **`open "https://…"`** always uses the user’s **default browser** (System Settings → Desktop & Dock → Default web browser).
- **DuckDuckGo Lucky** (`!ducky`): build `https://duckduckgo.com/?q=!ducky+<query>` (URL-encode spaces as `+` or `%20`) and run `open` on it via **`exec`**. The **first** search result opens in **one step**—use this to **play a song**, open a video, or land on the right page when the user has no exact link.
- For media keys / Now Playing, use **`exec`** with `osascript` or shell helpers as in the cookbook—not dedicated app tools.

Rules:
- **Play music / song / album / artist:** always append **`youtube`** to the Lucky search terms, then run **`exec`** with `open` and that Lucky URL. This helps DuckDuckGo Lucky land on a playable YouTube result more reliably.
- **Direct link known:** `action=open` with `url` (or `open "https://…"` from shell).
- When the user asks about **this page**, **current tab**, or **what is open in the browser**, first read the tab **title** and **URL**, then read the **visible page text** if needed.
- In **Microsoft Edge**, prefer `execute active tab of front window javascript "..."` to read live page content.
- Prefer the user's current selection first when they ask about highlighted text; otherwise read `main`, `article`, or `[role="main"]`, then fall back to `document.body`.
- Cap one capture to roughly **12k characters**. If the page is long, read it in chunks with `substring(start, end)` instead of trying to fetch everything at once.
- Some pages block scripting or render content inside complex canvases/iframes. If content comes back empty, tell the user and fall back to title + URL or try a simpler selector.
- Prefer simple actions: Lucky query, open URL, read front tab, close/reload tab.
- Use AppleScript/JXA only when you need a named browser or extra control.

Command cookbook:

Open a URL in the **default browser**:

```sh
open "https://example.com"
```

Open the **top DuckDuckGo result** for a song query—append **`youtube`** for music:

```sh
open "https://duckduckgo.com/?q=!ducky+taylor+swift+anti-hero+official+audio+youtube"
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

Read the current Microsoft Edge tab URL:

```sh
osascript -e 'tell application "Microsoft Edge" to return URL of active tab of front window'
```

Read the current Microsoft Edge tab title:

```sh
osascript -e 'tell application "Microsoft Edge" to return title of active tab of front window'
```

Read highlighted text from the current Microsoft Edge tab:

```sh
osascript -e 'tell application "Microsoft Edge" to execute active tab of front window javascript "(() => { const selected = window.getSelection ? String(window.getSelection()).trim() : \"\"; return selected.slice(0, 12000); })()"'
```

Read the main visible content from the current Microsoft Edge tab:

```sh
osascript -e 'tell application "Microsoft Edge" to execute active tab of front window javascript "(() => { const root = document.querySelector(\"main, article, [role=\\\"main\\\"]\") || document.body; return root && root.innerText ? root.innerText.slice(0, 12000) : \"\"; })()"'
```

Read a compact snapshot of the current Microsoft Edge tab with title, URL, and visible text:

```sh
osascript <<'APPLESCRIPT'
tell application "Microsoft Edge"
  set pageTitle to title of active tab of front window
  set pageURL to URL of active tab of front window
  set pageText to execute active tab of front window javascript "(() => { const selected = window.getSelection ? String(window.getSelection()).trim() : \"\"; if (selected) return selected.slice(0, 12000); const root = document.querySelector(\"main, article, [role=\\\"main\\\"]\") || document.body; return root && root.innerText ? root.innerText.slice(0, 12000) : \"\"; })()"
  return pageTitle & linefeed & pageURL & linefeed & linefeed & pageText
end tell
APPLESCRIPT
```

Read the next chunk from a long Microsoft Edge page:

```sh
osascript -e 'tell application "Microsoft Edge" to execute active tab of front window javascript "(() => { const root = document.querySelector(\"main, article, [role=\\\"main\\\"]\") || document.body; return root && root.innerText ? root.innerText.substring(12000, 24000) : \"\"; })()"'
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
