#!/usr/bin/env python3
"""Probe Gemini Robotics screen-position estimation from screenshots.

Usage:
  GEMINI_API_KEY=... python tools/gemini_robotics_screen_position_probe.py
  GEMINI_API_KEY=... python tools/gemini_robotics_screen_position_probe.py --trials 5
  GEMINI_API_KEY=... python tools/gemini_robotics_screen_position_probe.py --screenshot
  GEMINI_API_KEY=... python tools/gemini_robotics_screen_position_probe.py --screenshot --button "Continue"
  GEMINI_API_KEY=... python tools/gemini_robotics_screen_position_probe.py --image screen.png --prompt "Return the center of the search box."
"""

from __future__ import annotations

import argparse
import base64
import binascii
import html
import json
import math
import os
import random
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from pathlib import Path
from typing import Any


DEFAULT_MODEL = "gemini-robotics-er-1.6-preview"
DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_TIMEOUT = 180.0

TARGET_SPECS = [
    ("red_circle", "red circle", "circle", (230, 56, 64)),
    ("blue_square", "blue square", "square", (0, 122, 255)),
    ("green_triangle", "green triangle", "triangle", (52, 199, 89)),
    ("purple_diamond", "purple diamond", "diamond", (175, 82, 222)),
    ("orange_cross", "orange cross", "cross", (255, 149, 0)),
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Test Gemini Robotics screen coordinate estimation."
    )
    parser.add_argument(
        "--api-key",
        default=(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or "").strip(),
        help="Gemini API key. Defaults to GEMINI_API_KEY or GOOGLE_API_KEY.",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Default: {DEFAULT_MODEL}")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help=f"Default: {DEFAULT_BASE_URL}")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help=f"Default: {DEFAULT_TIMEOUT}")
    parser.add_argument("--trials", type=int, default=3, help="Synthetic benchmark trials. Default: 3")
    parser.add_argument("--width", type=int, default=1920, help="Synthetic screenshot width. Default: 1280")
    parser.add_argument("--height", type=int, default=1080, help="Synthetic screenshot height. Default: 720")
    parser.add_argument(
        "--screen-width",
        type=int,
        default=1920,
        help="Coordinate space width for real screenshots. Default: 1920",
    )
    parser.add_argument(
        "--screen-height",
        type=int,
        default=1080,
        help="Coordinate space height for real screenshots. Default: 1080",
    )
    parser.add_argument("--seed", type=int, default=17, help="Synthetic target placement seed. Default: 17")
    parser.add_argument("--tolerance", type=float, default=40.0, help="Pass threshold in pixels. Default: 40")
    parser.add_argument(
        "--out-dir",
        default="tools/screen_position_probe_runs",
        help="Directory for generated screenshots and JSON results.",
    )
    parser.add_argument(
        "--image",
        help="Use an existing screenshot instead of generated synthetic trials.",
    )
    parser.add_argument(
        "--screenshot",
        action="store_true",
        help="Capture the current macOS screen with screencapture before probing.",
    )
    parser.add_argument(
        "--prompt",
        help="Custom prompt for --image or --screenshot. Synthetic mode builds its own prompt.",
    )
    parser.add_argument(
        "--button",
        help="Button/control name to locate on a screenshot. If omitted with --screenshot, asks interactively.",
    )
    parser.add_argument("--raw", action="store_true", help="Print raw Gemini response JSON.")
    return parser


class Image:
    def __init__(self, width: int, height: int, color: tuple[int, int, int]) -> None:
        self.width = width
        self.height = height
        self.data = bytearray(color * width * height)

    def set_pixel(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return
        idx = (y * self.width + x) * 3
        self.data[idx : idx + 3] = bytes(color)

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
        x0 = max(0, min(self.width, x0))
        x1 = max(0, min(self.width, x1))
        y0 = max(0, min(self.height, y0))
        y1 = max(0, min(self.height, y1))
        for y in range(y0, y1):
            row = (y * self.width + x0) * 3
            self.data[row : row + (x1 - x0) * 3] = bytes(color) * (x1 - x0)

    def outline_rect(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int], width: int = 2) -> None:
        self.rect(x0, y0, x1, y0 + width, color)
        self.rect(x0, y1 - width, x1, y1, color)
        self.rect(x0, y0, x0 + width, y1, color)
        self.rect(x1 - width, y0, x1, y1, color)

    def circle(self, cx: int, cy: int, radius: int, color: tuple[int, int, int]) -> None:
        r2 = radius * radius
        for y in range(cy - radius, cy + radius + 1):
            for x in range(cx - radius, cx + radius + 1):
                if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
                    self.set_pixel(x, y, color)

    def triangle(self, cx: int, cy: int, size: int, color: tuple[int, int, int]) -> None:
        top = cy - size
        bottom = cy + size
        for y in range(top, bottom + 1):
            half_width = int((y - top) / max(1, bottom - top) * size)
            self.rect(cx - half_width, y, cx + half_width + 1, y + 1, color)

    def diamond(self, cx: int, cy: int, size: int, color: tuple[int, int, int]) -> None:
        for y in range(cy - size, cy + size + 1):
            half_width = size - abs(y - cy)
            self.rect(cx - half_width, y, cx + half_width + 1, y + 1, color)

    def cross(self, cx: int, cy: int, size: int, color: tuple[int, int, int]) -> None:
        arm = max(6, size // 4)
        self.rect(cx - arm, cy - size, cx + arm + 1, cy + size + 1, color)
        self.rect(cx - size, cy - arm, cx + size + 1, cy + arm + 1, color)

    def write_png(self, path: Path) -> None:
        def chunk(kind: bytes, payload: bytes) -> bytes:
            return (
                struct.pack(">I", len(payload))
                + kind
                + payload
                + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
            )

        rows = bytearray()
        stride = self.width * 3
        for y in range(self.height):
            rows.append(0)
            start = y * stride
            rows.extend(self.data[start : start + stride])

        path.parent.mkdir(parents=True, exist_ok=True)
        payload = b"".join(
            [
                b"\x89PNG\r\n\x1a\n",
                chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)),
                chunk(b"IDAT", zlib.compress(bytes(rows), level=6)),
                chunk(b"IEND", b""),
            ]
        )
        path.write_bytes(payload)


def draw_mock_screen(width: int, height: int, rng: random.Random) -> tuple[Image, list[dict[str, Any]]]:
    image = Image(width, height, (246, 247, 251))

    image.rect(0, 0, width, 34, (32, 34, 40))
    image.rect(0, height - 58, width, height, (231, 234, 240))
    image.rect(80, 74, width - 80, height - 94, (255, 255, 255))
    image.outline_rect(80, 74, width - 80, height - 94, (202, 207, 218), 2)
    image.rect(80, 74, width - 80, 120, (242, 244, 248))
    image.rect(112, 88, width - 250, 106, (224, 228, 236))
    image.rect(width - 225, 88, width - 112, 106, (210, 222, 255))
    image.rect(128, 154, width - 128, 176, (230, 233, 240))
    image.rect(128, 198, width - 320, 212, (235, 237, 243))
    image.rect(128, 234, width - 210, 248, (235, 237, 243))
    image.rect(128, 270, width - 360, 284, (235, 237, 243))

    targets: list[dict[str, Any]] = []
    used: list[tuple[int, int]] = []
    margin = 90
    target_size = 28

    for target_id, label, shape, color in TARGET_SPECS:
        for _ in range(200):
            x = rng.randint(margin, width - margin)
            y = rng.randint(135, height - margin - 20)
            if all(math.dist((x, y), point) > 135 for point in used):
                used.append((x, y))
                break
        else:
            x = rng.randint(margin, width - margin)
            y = rng.randint(135, height - margin - 20)

        image.circle(x, y, target_size + 8, (255, 255, 255))
        image.circle(x, y, target_size + 4, (30, 34, 42))
        if shape == "circle":
            image.circle(x, y, target_size, color)
        elif shape == "square":
            image.rect(x - target_size, y - target_size, x + target_size + 1, y + target_size + 1, color)
        elif shape == "triangle":
            image.triangle(x, y, target_size, color)
        elif shape == "diamond":
            image.diamond(x, y, target_size, color)
        elif shape == "cross":
            image.cross(x, y, target_size, color)

        targets.append({"id": target_id, "label": label, "x": x, "y": y})

    return image, targets


def synthetic_prompt(width: int, height: int, targets: list[dict[str, Any]]) -> str:
    target_lines = "\n".join(f"- {item['id']}: center of the {item['label']}" for item in targets)
    return f"""You are analyzing a screenshot.

The image size is {width}x{height} pixels. Use screen coordinates with origin at the top-left corner: x grows right, y grows down.

Find the center pixel coordinate of each target below:
{target_lines}

Return JSON only in this exact shape:
{{"points":[{{"id":"red_circle","x":123,"y":456}}]}}

Use the exact ids above. Do not include explanations."""


def button_location_prompt(button_name: str, screen_width: int, screen_height: int) -> str:
    return f"""You are analyzing a screenshot of the user's current screen.

The user's screen is 16:9 with a logical coordinate space of exactly {screen_width}x{screen_height} pixels.
Use screen coordinates with origin at the top-left corner: x grows right, y grows down.

Find the center point of this button or clickable UI control:
{button_name}

Return JSON only in this exact shape:
{{"target":"{button_name}","x":123,"y":456,"confidence":0.0,"reason":"short visual evidence"}}

Rules:
- x and y must be numbers in the {screen_width}x{screen_height} coordinate space.
- If there are multiple matching controls, choose the most prominent visible one.
- If the target is not visible, still return your best estimate and set confidence below 0.4.
- Do not include Markdown or explanations outside JSON."""


def read_image_as_part(path: Path) -> dict[str, Any]:
    suffix = path.suffix.lower()
    mime_type = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }.get(suffix, "image/png")
    return {
        "inline_data": {
            "mime_type": mime_type,
            "data": base64.b64encode(path.read_bytes()).decode("ascii"),
        }
    }


def generate_content(
    api_key: str,
    base_url: str,
    model: str,
    prompt: str,
    image_path: Path,
    timeout: float,
) -> dict[str, Any]:
    model_name = model.removeprefix("models/")
    url = (
        f"{base_url.rstrip('/')}/models/{urllib.parse.quote(model_name, safe='')}:generateContent"
        f"?key={urllib.parse.quote(api_key)}"
    )
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": prompt},
                    read_image_as_part(image_path),
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
        },
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except TimeoutError as exc:
        raise RuntimeError(
            f"Gemini request timed out after {timeout:.0f}s. "
            "Try a larger --timeout or check whether the model endpoint is slow."
        ) from exc
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gemini HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Gemini request failed: {exc.reason}") from exc


def extract_text(response: dict[str, Any]) -> str:
    candidate = ((response.get("candidates") or [None])[0]) or {}
    parts = (((candidate.get("content") or {}).get("parts")) or [])
    text = "\n".join(part.get("text", "") for part in parts if isinstance(part, dict)).strip()
    if not text:
        raise ValueError("Gemini response did not include text content")
    return text


def parse_json_text(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        cleaned = cleaned.removeprefix("json").strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start >= 0 and end >= start:
        cleaned = cleaned[start : end + 1]
    data = json.loads(cleaned)
    if not isinstance(data, dict):
        raise ValueError("Parsed response is not a JSON object")
    return data


def normalize_points(data: dict[str, Any]) -> dict[str, tuple[float, float]]:
    raw_points = data.get("points")
    if not isinstance(raw_points, list):
        raise ValueError("Expected JSON field 'points' to be a list")

    points: dict[str, tuple[float, float]] = {}
    for item in raw_points:
        if not isinstance(item, dict):
            continue
        point_id = item.get("id")
        x = item.get("x")
        y = item.get("y")
        if isinstance(point_id, str) and isinstance(x, (int, float)) and isinstance(y, (int, float)):
            points[point_id] = (float(x), float(y))
    return points


def extract_single_point(data: dict[str, Any]) -> tuple[float, float, float | None, str]:
    candidates: list[dict[str, Any]] = [data]
    for key in ("point", "position", "target"):
        value = data.get(key)
        if isinstance(value, dict):
            candidates.append(value)

    raw_points = data.get("points")
    if isinstance(raw_points, list):
        candidates.extend(item for item in raw_points if isinstance(item, dict))

    for item in candidates:
        x = item.get("x")
        y = item.get("y")
        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
            confidence = item.get("confidence")
            reason = item.get("reason")
            return (
                float(x),
                float(y),
                float(confidence) if isinstance(confidence, (int, float)) else None,
                str(reason) if reason is not None else "",
            )

    raise ValueError("Could not find numeric x/y fields in Gemini JSON response")


def write_annotated_svg(
    screenshot_path: Path,
    output_path: Path,
    x: float,
    y: float,
    label: str,
    screen_width: int,
    screen_height: int,
    response_text: str,
) -> None:
    image_data = base64.b64encode(screenshot_path.read_bytes()).decode("ascii")
    mime_type = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }.get(screenshot_path.suffix.lower(), "image/png")
    safe_label = html.escape(label)
    safe_response = html.escape(response_text[:600])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="{screen_width}" height="{screen_height}" viewBox="0 0 {screen_width} {screen_height}">
  <image href="data:{mime_type};base64,{image_data}" x="0" y="0" width="{screen_width}" height="{screen_height}" preserveAspectRatio="none"/>
  <circle cx="{x:.2f}" cy="{y:.2f}" r="34" fill="none" stroke="#ff2d55" stroke-width="6"/>
  <line x1="{x - 48:.2f}" y1="{y:.2f}" x2="{x + 48:.2f}" y2="{y:.2f}" stroke="#ff2d55" stroke-width="6" stroke-linecap="round"/>
  <line x1="{x:.2f}" y1="{y - 48:.2f}" x2="{x:.2f}" y2="{y + 48:.2f}" stroke="#ff2d55" stroke-width="6" stroke-linecap="round"/>
  <rect x="24" y="24" width="780" height="120" rx="18" fill="black" fill-opacity="0.72"/>
  <text x="48" y="70" fill="white" font-size="28" font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif">Target: {safe_label}</text>
  <text x="48" y="112" fill="white" font-size="24" font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif">Predicted center: ({x:.1f}, {y:.1f}) in {screen_width}x{screen_height}</text>
  <desc>{safe_response}</desc>
</svg>
""",
        encoding="utf-8",
    )


def score_points(
    expected: list[dict[str, Any]],
    predicted: dict[str, tuple[float, float]],
    tolerance: float,
) -> tuple[list[dict[str, Any]], float]:
    rows: list[dict[str, Any]] = []
    errors: list[float] = []
    for target in expected:
        point = predicted.get(target["id"])
        if point is None:
            rows.append({"id": target["id"], "missing": True, "pass": False})
            continue
        error = math.dist((target["x"], target["y"]), point)
        errors.append(error)
        rows.append(
            {
                "id": target["id"],
                "expected": [target["x"], target["y"]],
                "predicted": [round(point[0], 1), round(point[1], 1)],
                "error": round(error, 2),
                "pass": error <= tolerance,
            }
        )
    mean_error = sum(errors) / len(errors) if errors else float("inf")
    return rows, mean_error


def print_score(rows: list[dict[str, Any]], tolerance: float) -> None:
    for row in rows:
        if row.get("missing"):
            print(f"  {row['id']}: missing")
            continue
        status = "PASS" if row["pass"] else "FAIL"
        print(
            f"  {row['id']}: expected={row['expected']} predicted={row['predicted']} "
            f"error={row['error']}px {status}"
        )
    passed = sum(1 for row in rows if row.get("pass"))
    print(f"  passed={passed}/{len(rows)} tolerance={tolerance}px")


def run_synthetic(args: argparse.Namespace) -> int:
    if not args.api_key:
        print("Missing API key. Set GEMINI_API_KEY or GOOGLE_API_KEY.", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    all_errors: list[float] = []
    all_passes = 0
    all_targets = 0

    for trial in range(1, args.trials + 1):
        image, targets = draw_mock_screen(args.width, args.height, rng)
        image_path = out_dir / f"screen_position_trial_{trial:02d}.png"
        result_path = out_dir / f"screen_position_trial_{trial:02d}.json"
        image.write_png(image_path)

        prompt = synthetic_prompt(args.width, args.height, targets)
        print(f"\nTrial {trial}: {image_path}")
        response = generate_content(args.api_key, args.base_url, args.model, prompt, image_path, args.timeout)
        if args.raw:
            print(json.dumps(response, indent=2, ensure_ascii=False))

        text = extract_text(response)
        parsed = parse_json_text(text)
        predicted = normalize_points(parsed)
        rows, mean_error = score_points(targets, predicted, args.tolerance)
        all_errors.append(mean_error)
        all_passes += sum(1 for row in rows if row.get("pass"))
        all_targets += len(rows)
        print_score(rows, args.tolerance)

        result_path.write_text(
            json.dumps(
                {
                    "model": args.model,
                    "image": str(image_path),
                    "targets": targets,
                    "prompt": prompt,
                    "response_text": text,
                    "parsed": parsed,
                    "score": rows,
                    "mean_error": mean_error,
                },
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

    mean_of_means = sum(all_errors) / len(all_errors) if all_errors else float("inf")
    print(f"\nSummary: passed={all_passes}/{all_targets} mean_trial_error={mean_of_means:.2f}px")
    return 0 if all_passes == all_targets else 1


def capture_screenshot(out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"screenshot_{int(time.time())}.png"
    subprocess.run(["screencapture", "-x", str(path)], check=True)
    return path


def normalize_image_for_screen(
    image_path: Path,
    out_dir: Path,
    screen_width: int,
    screen_height: int,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    output_path = out_dir / f"{image_path.stem}_{screen_width}x{screen_height}.png"
    if image_path.resolve() == output_path.resolve():
        return image_path

    try:
        subprocess.run(
            [
                "sips",
                "-s",
                "format",
                "png",
                "-z",
                str(screen_height),
                str(screen_width),
                str(image_path),
                "--out",
                str(output_path),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        return output_path
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"Warning: could not resize image to {screen_width}x{screen_height}; using original. {exc}", file=sys.stderr)
        return image_path


def run_single_image(args: argparse.Namespace) -> int:
    if not args.api_key:
        print("Missing API key. Set GEMINI_API_KEY or GOOGLE_API_KEY.", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir)
    should_capture = args.screenshot or (args.button and not args.image)
    raw_image_path = capture_screenshot(out_dir) if should_capture else Path(args.image)
    if not raw_image_path.exists():
        print(f"Image not found: {raw_image_path}", file=sys.stderr)
        return 2

    button_name = args.button
    if args.screenshot and not args.prompt and not button_name:
        button_name = input("Nhập tên nút/control cần xác định vị trí: ").strip()
    if args.button and args.prompt:
        print("Use either --button or --prompt, not both.", file=sys.stderr)
        return 2
    if button_name:
        prompt = button_location_prompt(button_name, args.screen_width, args.screen_height)
    elif args.prompt:
        prompt = args.prompt
    else:
        print("--prompt or --button is required with --image. With --screenshot, omit both to enter interactively.", file=sys.stderr)
        return 2

    image_path = raw_image_path
    if button_name:
        image_path = normalize_image_for_screen(raw_image_path, out_dir, args.screen_width, args.screen_height)

    print(f"Screenshot/image: {raw_image_path}")
    if image_path != raw_image_path:
        print(f"Model input image: {image_path}")
    print(f"Coordinate space: {args.screen_width}x{args.screen_height} (16:9)")
    if button_name:
        print(f"Target button/control: {button_name}")

    try:
        response = generate_content(args.api_key, args.base_url, args.model, prompt, image_path, args.timeout)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    if args.raw:
        print(json.dumps(response, indent=2, ensure_ascii=False))

    text = extract_text(response)
    print(text)

    if button_name:
        parsed = parse_json_text(text)
        x, y, confidence, reason = extract_single_point(parsed)
        run_id = int(time.time())
        annotated_path = out_dir / f"button_location_{run_id}.svg"
        result_path = out_dir / f"button_location_{run_id}.json"
        write_annotated_svg(
            image_path,
            annotated_path,
            x,
            y,
            button_name,
            args.screen_width,
            args.screen_height,
            text,
        )
        result_path.write_text(
            json.dumps(
                {
                    "model": args.model,
                    "image": str(image_path),
                    "annotated_image": str(annotated_path),
                    "coordinate_space": [args.screen_width, args.screen_height],
                    "target": button_name,
                    "x": x,
                    "y": y,
                    "confidence": confidence,
                    "reason": reason,
                    "prompt": prompt,
                    "response_text": text,
                    "parsed": parsed,
                },
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        print(f"Annotated image saved: {annotated_path}")
        print(f"Result JSON saved: {result_path}")
    return 0


def main() -> int:
    args = build_parser().parse_args()
    if args.image or args.screenshot or args.button:
        return run_single_image(args)
    return run_synthetic(args)


if __name__ == "__main__":
    raise SystemExit(main())
