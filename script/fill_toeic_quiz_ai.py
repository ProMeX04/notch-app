#!/usr/bin/env python3
"""Generate TOEIC Part-5 style MCQs for every vocab word via local proxy.

Proxy: http://localhost:20128/v1
Model: gemini/gemini-3.1-flash-lite-preview

Writes / merges into Sources/Notch/Resources/TOEIC/toeic_quiz.json
IDs: ai-cloze-{wordId}
Keeps offline meaning-* items; replaces/updates ai-cloze and old cloze-* for same word.
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
QUIZ_PATH = ROOT / "Sources/Notch/Resources/TOEIC/toeic_quiz.json"

BASE_URL = "http://localhost:20128/v1"
MODEL = "gemini/gemini-3.1-flash-lite-preview"
BATCH_SIZE = 8
MAX_WORKERS = 4
MAX_RETRIES = 6

file_lock = Lock()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_quiz(items: list[dict]) -> None:
    tmp = QUIZ_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(QUIZ_PATH)


def call_chat(batch: list[dict]) -> list[dict]:
    lines = []
    for r in batch:
        lines.append(
            f"{r['id']}|{r.get('word','')}|{r.get('pos','')}|{(r.get('meaning') or '')[:80]}|"
            f"{(r.get('example') or '')[:100]}"
        )
    prompt = (
        "You are a professional TOEIC Part 5 writer.\n"
        "For EACH word below, create ONE business-English multiple-choice item.\n\n"
        "Return ONLY a JSON array of objects with keys:\n"
        "  wordId (int), word (string), prompt (string), choices (array of 4 strings),\n"
        "  answer (string), explanationVI (string), translationVI (string)\n\n"
        "Rules:\n"
        "- prompt: realistic workplace English, EXACTLY one blank as _____\n"
        "  Never write meta lines like 'The best word for this context is _____'.\n"
        "- The correct option MUST be the headword (same spelling as `word`) OR a common\n"
        "  inflection that still clearly tests that headword; prefer exact headword.\n"
        "- choices: exactly 4 DISTINCT options (same POS when possible); shuffle order.\n"
        "- answer: must equal one of choices exactly.\n"
        "- explanationVI: short Vietnamese note (why correct / tip).\n"
        "- translationVI: full Vietnamese of the completed English sentence.\n"
        "- No markdown fences, no commentary outside JSON.\n\n"
        "Words (id|word|pos|meaning|example_hint):\n" + "\n".join(lines)
    )
    body = {
        "model": MODEL,
        "stream": False,
        "temperature": 0.5,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=150) as resp:
        raw = json.loads(resp.read().decode("utf-8"))
    text = raw["choices"][0]["message"]["content"]
    if isinstance(text, list):
        text = "".join(p.get("text", "") if isinstance(p, dict) else str(p) for p in text)
    text = (text or "").strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    data = json.loads(text)
    if isinstance(data, dict):
        for key in ("items", "data", "results", "questions", "quiz"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
    if not isinstance(data, list):
        m = re.search(r"\[[\s\S]*\]", text)
        if not m:
            raise ValueError(f"bad shape: {text[:240]}")
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
            time.sleep(1.4 * (attempt + 1) + random.random())
        except Exception as e:
            last_err = e
            time.sleep(1.0 * (attempt + 1) + random.random())
    raise RuntimeError(f"Batch failed: {last_err}")


def normalize_item(raw: dict, vocab_by_id: dict[int, dict]) -> dict | None:
    try:
        word_id = int(raw.get("wordId") or raw.get("id") or raw.get("word_id"))
    except Exception:
        return None
    word = (raw.get("word") or vocab_by_id.get(word_id, {}).get("word") or "").strip()
    prompt = (raw.get("prompt") or "").strip()
    choices = raw.get("choices") or raw.get("options") or []
    if isinstance(choices, str):
        choices = [c.strip() for c in choices.split("|") if c.strip()]
    choices = [str(c).strip() for c in choices if str(c).strip()]
    # dedupe preserve order
    seen = set()
    uniq = []
    for c in choices:
        k = c.lower()
        if k in seen:
            continue
        seen.add(k)
        uniq.append(c)
    choices = uniq
    answer = (raw.get("answer") or "").strip()
    if not prompt or "_____" not in prompt or len(choices) < 4:
        return None
    choices = choices[:4]
    if answer and answer not in choices:
        # try case-insensitive match
        for i, c in enumerate(choices):
            if c.lower() == answer.lower():
                answer = c
                break
        else:
            # force headword as answer if present
            if word in choices:
                answer = word
            else:
                choices[0] = word or answer
                answer = choices[0]
    if not answer:
        if word in choices:
            answer = word
        else:
            return None
    # Always shuffle so correct answer is not stuck at A.
    random.shuffle(choices)
    correct_index = choices.index(answer)
    pos = (vocab_by_id.get(word_id, {}).get("pos") or "Vocab").strip() or "Vocab"
    return {
        "id": f"ai-cloze-{word_id}",
        "wordId": word_id,
        "word": word,
        "type": "cloze",
        "prompt": prompt,
        "choices": choices,
        "correctIndex": correct_index,
        "explanationVI": (raw.get("explanationVI") or raw.get("explanation") or "").strip(),
        "translationVI": (raw.get("translationVI") or raw.get("translation") or "").strip(),
        "part": pos if pos != "Word" else "Vocab",
        "source": "ai",
    }


def merge_ai_items(new_items: list[dict]) -> int:
    """Insert/replace ai-cloze items; drop old offline cloze-* for same wordId."""
    if not new_items:
        return 0
    with file_lock:
        quiz = load_json(QUIZ_PATH) if QUIZ_PATH.exists() else []
        by_id = {q.get("id"): q for q in quiz if isinstance(q, dict) and q.get("id")}
        word_ids = {int(it["wordId"]) for it in new_items if "wordId" in it}

        # remove superseded offline cloze for those words
        for wid in word_ids:
            by_id.pop(f"cloze-{wid}", None)

        filled = 0
        for it in new_items:
            by_id[it["id"]] = it
            filled += 1

        # stable-ish order: keep meaning-*, then ai-cloze by wordId, then other
        items = list(by_id.values())

        def sort_key(q: dict):
            qid = q.get("id") or ""
            if qid.startswith("meaning-"):
                try:
                    return (0, int(qid.split("-", 1)[1]))
                except Exception:
                    return (0, 0)
            if qid.startswith("ai-cloze-"):
                try:
                    return (1, int(qid.split("-", 2)[2]))
                except Exception:
                    return (1, 0)
            if qid.startswith("cloze-"):
                try:
                    return (2, int(qid.split("-", 1)[1]))
                except Exception:
                    return (2, 0)
            return (3, qid)

        items.sort(key=sort_key)
        save_quiz(items)
    return filled


def main() -> None:
    vocab = load_json(VOCAB_PATH)
    vocab_by_id = {int(r["id"]): r for r in vocab}

    existing = load_json(QUIZ_PATH) if QUIZ_PATH.exists() else []
    have_ai = {
        int(q["wordId"])
        for q in existing
        if isinstance(q, dict) and str(q.get("id", "")).startswith("ai-cloze-") and q.get("wordId") is not None
    }
    # also count completed via id parse
    for q in existing:
        qid = str(q.get("id") or "")
        if qid.startswith("ai-cloze-"):
            try:
                have_ai.add(int(qid.split("-", 2)[2]))
            except Exception:
                pass

    pending = [r for r in vocab if int(r["id"]) not in have_ai]
    print(
        f"proxy={BASE_URL} model={MODEL}\n"
        f"vocab={len(vocab)} existing_quiz={len(existing)} "
        f"ai_done={len(have_ai)} pending={len(pending)}"
    )
    if not pending:
        print("Nothing to do.")
        return

    batches = [pending[i : i + BATCH_SIZE] for i in range(0, len(pending), BATCH_SIZE)]
    done = 0
    failed = 0
    completed = 0
    t0 = time.time()

    def process(batch: list[dict]) -> tuple[int, int]:
        raw = generate_batch(batch)
        items = []
        for r in raw:
            norm = normalize_item(r, vocab_by_id)
            if norm:
                items.append(norm)
        # fallback: if model missed some ids, leave for retry later
        filled = merge_ai_items(items)
        return filled, len(batch)

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
                    f"ai_items≈{done} ({rate:.1f}/s)",
                    flush=True,
                )
            except Exception as e:
                failed += 1
                print(f"BATCH ERROR: {e}", flush=True)

    # final stats
    quiz = load_json(QUIZ_PATH)
    ai_n = sum(1 for q in quiz if str(q.get("id", "")).startswith("ai-cloze-"))
    meaning_n = sum(1 for q in quiz if str(q.get("id", "")).startswith("meaning-"))
    cloze_n = sum(1 for q in quiz if str(q.get("id", "")).startswith("cloze-"))
    print(
        f"Done. total_quiz={len(quiz)} ai_cloze={ai_n} meaning={meaning_n} "
        f"offline_cloze_left={cloze_n} failed={failed} elapsed={time.time()-t0:.0f}s"
    )


if __name__ == "__main__":
    main()
