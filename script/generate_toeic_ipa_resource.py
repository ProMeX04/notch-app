#!/usr/bin/env python3
"""Generate bundled TOEIC IPA resources (offline — not at app runtime).

Writes:
  Sources/Notch/Resources/TOEIC/toeic_phonetics.json   # { "word": "/ipa/" }
  Sources/Notch/Resources/TOEIC/toeic_vocabulary.json  # fills pronunciation fields

Modes:
  --mode local   eng_to_ipa dictionary (fast, default)
  --mode ai      OpenAI-compatible gateway batches (slow; set TOEIC_IPA_API / TOEIC_IPA_MODEL)

Usage:
  python3 script/generate_toeic_ipa_resource.py
  python3 script/generate_toeic_ipa_resource.py --mode ai
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOCAB = ROOT / "Sources/Notch/Resources/TOEIC/toeic_vocabulary.json"
OUT = ROOT / "Sources/Notch/Resources/TOEIC/toeic_phonetics.json"
DEFAULT_API = "http://localhost:20128/v1/chat/completions"
DEFAULT_MODEL = "gemini/gemini-3.1-flash-lite-preview"


def ensure_eng_to_ipa():
    try:
        import eng_to_ipa as e2i  # type: ignore

        return e2i
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "eng-to-ipa", "-q"])
        import eng_to_ipa as e2i  # type: ignore

        return e2i


def wrap_ipa(s: str) -> str:
    s = (s or "").strip().strip("/")
    if not s or "*" in s:
        return ""
    if re.fullmatch(r"[A-Za-z' .\-]+", s):
        return ""
    return f"/{s}/"


def local_ipa(e2i, word: str) -> str:
    try:
        raw = e2i.convert(word)
    except Exception:
        return ""
    if not raw or "*" in raw:
        return ""
    return wrap_ipa(raw)


def ai_batch(api: str, model: str, words: list[str]) -> dict[str, str]:
    schema = {
        "type": "object",
        "properties": {
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "word": {"type": "string"},
                        "ipa": {"type": "string"},
                    },
                    "required": ["word", "ipa"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["items"],
        "additionalProperties": False,
    }
    body = {
        "model": model,
        "stream": False,
        "temperature": 0,
        "max_tokens": 2500,
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": "ipa_batch", "strict": True, "schema": schema},
        },
        "messages": [
            {
                "role": "system",
                "content": (
                    "You output General American IPA for English headwords. "
                    "JSON only: {items:[{word, ipa}]}. ipa like /ˈæp.əl/ with slashes. "
                    "Same words and count as input."
                ),
            },
            {"role": "user", "content": "IPA for:\n" + "\n".join(words)},
        ],
    }
    req = urllib.request.Request(
        api,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=90) as resp:
        payload = json.loads(resp.read().decode())
    content = payload["choices"][0]["message"]["content"].strip()
    if content.startswith("```"):
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)
    start, end = content.find("{"), content.rfind("}")
    if start >= 0 and end > start:
        content = content[start : end + 1]
    data = json.loads(content)
    out: dict[str, str] = {}
    for it in data.get("items") or []:
        w = str(it.get("word") or "").strip().lower()
        ipa = wrap_ipa(str(it.get("ipa") or ""))
        if w and ipa:
            out[w] = ipa
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=("local", "ai"), default="local")
    p.add_argument("--api", default=None)
    p.add_argument("--model", default=None)
    p.add_argument("--batch-size", type=int, default=40)
    args = p.parse_args()

    rows = json.loads(VOCAB.read_text())
    order: list[str] = []
    seen: set[str] = set()
    for r in rows:
        w = (r.get("word") or "").strip()
        if not w or len(w) < 2:
            continue
        k = w.lower()
        if k in seen:
            continue
        seen.add(k)
        order.append(w)

    result: dict[str, str] = {}
    e2i = ensure_eng_to_ipa()

    if args.mode == "ai":
        api = args.api or __import__("os").environ.get("TOEIC_IPA_API", DEFAULT_API)
        model = args.model or __import__("os").environ.get("TOEIC_IPA_MODEL", DEFAULT_MODEL)
        print(f"AI mode → {api} model={model}")
        for i in range(0, len(order), args.batch_size):
            chunk = order[i : i + args.batch_size]
            try:
                got = ai_batch(api, model, chunk)
                result.update(got)
                print(f"  {min(i + args.batch_size, len(order))}/{len(order)} ({len(result)} ipa)")
            except Exception as e:
                print(f"  batch fail @ {i}: {e}")
            time.sleep(0.3)

    # Always fill gaps with local dictionary
    for w in order:
        k = w.lower()
        if k not in result:
            ipa = local_ipa(e2i, w)
            if ipa:
                result[k] = ipa

    for r in rows:
        w = (r.get("word") or "").strip().lower()
        if w in result:
            r["pronunciation"] = result[w].strip("/")

    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    VOCAB.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
    filled = sum(1 for r in rows if (r.get("pronunciation") or "").strip())
    print(f"wrote {OUT} ({len(result)} entries)")
    print(f"vocab pronunciation filled {filled}/{len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
