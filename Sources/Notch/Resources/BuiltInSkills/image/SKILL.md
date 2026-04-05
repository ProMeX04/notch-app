---
name: image
description: Use when the user wants to search, show, download, or copy an image, wallpaper, illustration, or visual reference.
icon: photo.on.rectangle
category: builtin
requiredTools: ["exec"]
memory: false
---

# Image

Use this skill when the user wants to find an image, show it in Notch, save it locally, or put the file on the clipboard.

Rules:
- Use short, concrete search phrases.
- Prefer a single strong visual concept over a long sentence when searching.
- Do not use this skill if the user only wants textual description.
- Use `~/.notch/bin/notchctl image ...` through `exec` for Notch image overlay actions.
- Prefer `image search` or `image show` for search-style requests.
- Prefer `image url` or `image file` when the image source is already known.
- Save downloaded files under `~/.notch/workspace/images/` unless the user asks for another location.
- Use `curl -L` for direct image downloads.
- Copy image files with AppleScript when the user wants the file itself on the clipboard.
- Use `landscape` unless the user clearly asks for portrait or square.
- Add a short caption only when it improves clarity.

Command cookbook:

Search:
```sh
~/.notch/bin/notchctl image search "red panda wallpaper" landscape
```

Show:
```sh
~/.notch/bin/notchctl image show "samurai portrait illustration" portrait
```

Show a direct image URL:
```sh
~/.notch/bin/notchctl image url "https://images.example.com/picture.jpg" "samurai portrait"
```

Show a local image file:
```sh
~/.notch/bin/notchctl image file "/path/to/image.png" "reference"
```

Download:
```sh
mkdir -p ~/.notch/workspace/images
curl -L "https://images.example.com/picture.jpg" -o ~/.notch/workspace/images/picture.jpg
```

Copy:
```sh
image_path="$HOME/.notch/workspace/images/picture.jpg"
osascript -e "set the clipboard to (POSIX file \"$image_path\")"
```

Clear the current overlay image:
```sh
~/.notch/bin/notchctl image clear
```
