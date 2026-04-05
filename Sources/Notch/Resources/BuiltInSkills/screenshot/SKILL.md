---
name: screenshot
description: Use when the user wants a screenshot taken, saved to a file, or copied to the clipboard.
icon: camera.viewfinder
category: builtin
requiredTools: ["exec"]
memory: false
---

# Screenshot

Use this skill when the user wants to capture the screen, a region, or a specific window.

Rules:
- Use `screencapture` through `exec`.
- Save screenshots inside `~/.notch/workspace/screenshots` unless the user clearly asks for another location.
- That screenshots folder already exists by default in the workspace.
- Prefer non-interactive capture when the target is already clear.
- Use interactive region or window capture only when the user expects to click or drag on screen.
- Tell the user where the screenshot was saved, or that it was copied to the clipboard.

Command cookbook:

Capture the full screen to a file:
```sh
screencapture -x ~/.notch/workspace/screenshots/fullscreen-$(date +%Y%m%d-%H%M%S).png
```

Capture an interactively selected region to a file:
```sh
screencapture -iW ~/.notch/workspace/screenshots/window-$(date +%Y%m%d-%H%M%S).png
```

Capture an interactively selected area to a file:
```sh
screencapture -i ~/.notch/workspace/screenshots/region-$(date +%Y%m%d-%H%M%S).png
```

Capture the full screen to the clipboard:
```sh
screencapture -cx
```

Capture an interactively selected region to the clipboard:
```sh
screencapture -ci
```
