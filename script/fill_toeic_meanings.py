#!/usr/bin/env python3
"""Enrich TOEIC vocabulary with multi-sense meanings + part of speech.

Proxy: http://localhost:20128/v1
Model: gemini/gemini-3.1-flash-lite-preview

Merges into disk on every batch so concurrent example-fill cannot wipe progress
(and we never wipe examples).
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
BATCH_SIZE = 15
MAX_WORKERS = 2
MAX_RETRIES = 6

file_lock = Lock()


def load() -> list[dict]:
    return json.loads(VOCAB_PATH.read_text(encoding="utf-8"))


def save(items: list[dict]) -> None:
    tmp = VOCAB_PATH.with_suffix(".json.tmp")
    tmp.write_text(
        json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    tmp.replace(VOCAB_PATH)


def needs_enrich(row: dict) -> bool:
    pos = (row.get("pos") or "").strip()
    meaning = (row.get("meaning") or "").strip()
    meaning_en = (row.get("meaning_en") or "").strip()
    if pos in ("", "Word", "word"):
        return True
    if not meaning_en:
        return True
    if "(" not in meaning and ";" not in meaning and "," not in meaning and len(meaning) < 18:
        return True
    return False


def call_chat(batch: list[dict]) -> list[dict]:
    lines = [
        f"{row['id']}|{row.get('word', '')}|{(row.get('meaning') or '').strip()}"
        for row in batch
    ]
    prompt = (
        "You are a TOEIC dictionary editor.\n"
        "For EACH English headword below, expand dictionary data.\n\n"
        "Return ONLY a JSON array of objects with keys:\n"
        '  id (int), pos (string), meaning (string), meaning_en (string)\n\n'
        "Rules:\n"
        "- pos: short tags n. v. adj. adv. prep. conj. pron. int. det.\n"
        "  Multiple POS: \"v., n.\"\n"
        "- meaning: Vietnamese, 2–4 senses when useful.\n"
        "  Format: \"(v.) nghĩa1, nghĩa2; (n.) nghĩa3\" — label sense groups with POS.\n"
        "  Prefer TOEIC/business senses first.\n"
        "- meaning_en: English glosses in the same multi-sense style.\n"
        "- Keep concise. No markdown, no commentary.\n\n"
        "Words (id|word|current_vi):\n" + "\n".join(lines)
    )
    body = {
        "model": MODEL,
        "stream": False,
        "temperature": 0.35,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = json.loads(resp.read().decode("utf-8"))
    text = raw["choices"][0]["message"]["content"]
    if isinstance(text, list):
        text = "".join(
            p.get("text", "") if isinstance(p, dict) else str(p) for p in text
        )
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    data = json.loads(text)
    if isinstance(data, dict):
        for key in ("items", "data", "results", "words"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
    if not isinstance(data, list):
        m = re.search(r"\[[\s\S]*\]", text)
        if not m:
            raise ValueError(f"bad shape: {text[:200]}")
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
            time.sleep(1.5 * (attempt + 1) + random.random())
        except Exception as e:
            last_err = e
            time.sleep(1.0 * (attempt + 1) + random.random())
    raise RuntimeError(f"Batch failed: {last_err}")


def apply_results(results: list[dict]) -> int:
    """Merge meaning fields into current disk file; preserve examples."""
    by_id: dict[int, dict] = {}
    for r in results:
        try:
            rid = int(r["id"])
        except Exception:
            continue
        meaning = (r.get("meaning") or "").strip()
        if not meaning:
            continue
        pos = (r.get("pos") or "").strip() or "n."
        meaning_en = (r.get("meaning_en") or "").strip()
        by_id[rid] = {"pos": pos, "meaning": meaning, "meaning_en": meaning_en}

    if not by_id:
        return 0

    with file_lock:
        items = load()
        filled = 0
        for row in items:
            rid = int(row["id"])
            if rid not in by_id:
                continue
            upd = by_id[rid]
            row["pos"] = upd["pos"]
            row["meaning"] = upd["meaning"]
            if upd["meaning_en"]:
                row["meaning_en"] = upd["meaning_en"]
            filled += 1
        save(items)
    return filled


def main() -> None:
    items = load()
    pending_ids = [int(row["id"]) for row in items if needs_enrich(row)]
    id_to_row = {int(r["id"]): r for r in items}
    print(
        f"proxy={BASE_URL} model={MODEL}\n"
        f"total={len(items)} need_enrich={len(pending_ids)}"
    )
    if not pending_ids:
        print("Nothing to do.")
        return

    batches = [
        pending_ids[i : i + BATCH_SIZE]
        for i in range(0, len(pending_ids), BATCH_SIZE)
    ]
    done = 0
    failed = 0
    completed = 0
    t0 = time.time()

    def process(ids: list[int]) -> tuple[int, int]:
        batch_rows = [id_to_row[i] for i in ids if i in id_to_row]
        # refresh meaning snapshot from disk for current_vi hints
        with file_lock:
            disk = {int(r["id"]): r for r in load()}
        batch_rows = [disk.get(i, id_to_row[i]) for i in ids]
        results = generate_batch(batch_rows)
        filled = apply_results(results)
        return filled, len(ids)

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futs = {pool.submit(process, b): b for b in batches}
        for fut in as_completed(futs):
            try:
                filled, total = fut.result()
                done += filled
                completed += 1
                elapsed = time.time() - t0
                rate = done / elapsed if elapsed else 0
                print(
                    f"[{completed}/{len(batches)}] +{filled}/{total} "
                    f"done≈{done} ({rate:.1f}/s)",
                    flush=True,
                )
            except Exception as e:
                failed += 1
                print(f"BATCH ERROR: {e}", flush=True)

    still = sum(1 for r in load() if needs_enrich(r))
    print(f"Done. still_need={still} failed={failed} elapsed={time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
