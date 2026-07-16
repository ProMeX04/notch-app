#!/usr/bin/env python3
"""Pre-fill missing TOEIC example sentences via local OpenAI-compatible proxy.

Proxy: http://localhost:20128/v1
Model: gemini/gemini-3.1-flash-lite-preview

Writes Sources/Notch/Resources/TOEIC/toeic_vocabulary.json incrementally.
"""

from __future__ import annotations

import json
import random
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from threading import Lock

ROOT = Path(__file__).resolve().parents[1]
VOCAB_PATH = ROOT / "Sources/Notch/Resources/TOEIC/toeic_vocabulary.json"

BASE_URL = "http://localhost:20128/v1"
MODEL = "gemini/gemini-3.1-flash-lite-preview"
BATCH_SIZE = 20
MAX_WORKERS = 3
MAX_RETRIES = 6


def call_chat(batch: list[dict]) -> list[dict]:
    lines = []
    for row in batch:
        wid = row["id"]
        word = row.get("word", "")
        meaning = (row.get("meaning") or "").strip()
        lines.append(f"{wid}|{word}|{meaning}")

    prompt = (
        "You write TOEIC / business-English study examples.\n"
        "For EACH word below, write:\n"
        "1) one natural English example sentence that CONTAINS the headword (exact spelling),\n"
        "2) a natural Vietnamese translation of that sentence.\n"
        "Return ONLY a JSON array of objects: "
        '[{"id": <int>, "example": "...", "example_vn": "..."}]\n'
        "No markdown fences, no commentary. Keep sentences concise (8–20 words).\n\n"
        "Words (id|word|vi_meaning):\n" + "\n".join(lines)
    )

    body = {
        "model": MODEL,
        "stream": False,
        "temperature": 0.45,
        "messages": [{"role": "user", "content": prompt}],
    }
    url = f"{BASE_URL}/chat/completions"
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = json.loads(resp.read().decode("utf-8"))

    text = raw["choices"][0]["message"]["content"]
    if isinstance(text, list):
        # some proxies return content parts
        text = "".join(
            p.get("text", "") if isinstance(p, dict) else str(p) for p in text
        )
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)

    data = json.loads(text)
    if isinstance(data, dict):
        data = data.get("items") or data.get("examples") or data.get("data") or []
        # sometimes model wraps as {"results":[...]} 
        if not data:
            for v in data.values() if isinstance(data, dict) else []:
                if isinstance(v, list):
                    data = v
                    break
    if not isinstance(data, list):
        # try extract array substring
        m = re.search(r"\[[\s\S]*\]", text)
        if not m:
            raise ValueError(f"Unexpected JSON shape: {type(data)} / {text[:200]}")
        data = json.loads(m.group(0))
    return data


def generate_batch(batch: list[dict]) -> list[dict]:
    last_err: Exception | None = None
    for attempt in range(MAX_RETRIES):
        try:
            return call_chat(batch)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")[:400]
            last_err = RuntimeError(f"HTTP {e.code}: {body}")
            time.sleep(1.2 * (attempt + 1) + random.random())
        except Exception as e:
            last_err = e
            time.sleep(0.8 * (attempt + 1) + random.random())
    raise RuntimeError(f"Batch failed after retries: {last_err}")


def main() -> None:
    items: list[dict] = json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
    pending_idx = [
        i for i, row in enumerate(items) if not (row.get("example") or "").strip()
    ]
    # Also re-fill weak offline scaffolds left by previous direct-API run
    weak_prefixes = (
        "In business English,",
        "The report mentioned",
        'The manager mentioned "',
    )
    weak_idx = [
        i
        for i, row in enumerate(items)
        if any((row.get("example") or "").startswith(p) for p in weak_prefixes)
    ]
    # Only process true empties first; weak can be optional second pass
    print(
        f"proxy={BASE_URL} model={MODEL}\n"
        f"total={len(items)} empty={len(pending_idx)} weak_scaffold={len(weak_idx)}"
    )
    if not pending_idx:
        print("No empty examples left.")
        return

    batches: list[list[int]] = []
    for i in range(0, len(pending_idx), BATCH_SIZE):
        batches.append(pending_idx[i : i + BATCH_SIZE])

    file_lock = Lock()
    done = 0
    failed_batches = 0
    t0 = time.time()
    completed_batches = 0
    save_every = 3

    def process(batch_indices: list[int]) -> tuple[int, int]:
        # Snapshot current rows for the prompt (re-read disk so we keep latest meanings).
        with file_lock:
            disk = json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
        batch_rows = [disk[i] for i in batch_indices]
        results = generate_batch(batch_rows)
        by_id: dict[int, tuple[str, str]] = {}
        for r in results:
            try:
                rid = int(r["id"])
            except Exception:
                continue
            ex = (r.get("example") or "").strip()
            vn = (r.get("example_vn") or "").strip()
            if ex:
                by_id[rid] = (ex, vn)
        filled = 0
        with file_lock:
            # Merge into latest disk — never clobber pos/meaning from other jobs.
            disk = json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
            for row in disk:
                rid = int(row["id"])
                if rid not in by_id:
                    continue
                if (row.get("example") or "").strip():
                    continue  # already filled
                ex, vn = by_id[rid]
                row["example"] = ex
                if vn:
                    row["example_vn"] = vn
                filled += 1
            tmp = VOCAB_PATH.with_suffix(".json.tmp")
            tmp.write_text(
                json.dumps(disk, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            tmp.replace(VOCAB_PATH)
            print(f"  saved → {VOCAB_PATH}", flush=True)
        return filled, len(batch_indices)

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(process, b): b for b in batches}
        for fut in as_completed(futures):
            try:
                filled, total = fut.result()
                done += filled
                completed_batches += 1
                elapsed = time.time() - t0
                rate = done / elapsed if elapsed else 0
                print(
                    f"[{completed_batches}/{len(batches)}] +{filled}/{total} "
                    f"filled≈{done} ({rate:.1f}/s)",
                    flush=True,
                )
            except Exception as e:
                failed_batches += 1
                print(f"BATCH ERROR: {e}", flush=True)

    still = sum(
        1
        for r in json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
        if not (r.get("example") or "").strip()
    )
    print(
        f"Done. still_empty={still} failed_batches={failed_batches} "
        f"elapsed={time.time()-t0:.0f}s"
    )


if __name__ == "__main__":
    main()
