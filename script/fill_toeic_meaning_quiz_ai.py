#!/usr/bin/env python3
"""Replace easy offline meaning MCQs with TOEIC-style AI “closest in meaning” items.

Proxy: http://localhost:20128/v1
Model: gemini/gemini-3.1-flash-lite-preview

Writes ai-meaning-{wordId} into toeic_quiz.json and removes offline meaning-{id}.
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


def primary_meaning(meaning: str) -> str:
    m = (meaning or "").strip()
    if not m:
        return ""
    first = m.split(";")[0].strip()
    first = re.sub(r"^\([^)]+\)\s*", "", first).strip()
    return first or m


def call_chat(batch: list[dict]) -> list[dict]:
    lines = []
    for r in batch:
        lines.append(
            f"{r['id']}|{r.get('word','')}|{r.get('pos','')}|"
            f"{primary_meaning(r.get('meaning') or '')}|"
            f"{(r.get('meaning_en') or '')[:90]}"
        )
    prompt = (
        "You write Vietnamese multiple-choice vocabulary items for TOEIC learners.\n"
        "For EACH English headword, create ONE item testing its Vietnamese meaning.\n\n"
        "Return ONLY a JSON array of objects:\n"
        "  wordId (int), word (string), prompt (string),\n"
        "  choices (array of 4 Vietnamese strings), answer (string), explanationVI (string)\n\n"
        "Rules:\n"
        "- prompt: Nghĩa của từ \"{word}\" gần nhất với:\n"
        "- choices: exactly 4 DISTINCT Vietnamese meaning options (short phrases).\n"
        "  Correct = the true main Vietnamese sense of the word (can polish the bank meaning).\n"
        "  Distractors = NEAR-MISS Vietnamese meanings: same POS, related topic/domain,\n"
        "  easy to confuse but WRONG (e.g. trì hoãn vs hủy bỏ; tăng vs giảm; thuê vs mua).\n"
        "  Do NOT use obviously random wrong meanings like 'con mèo' for a business verb.\n"
        "  Do NOT use English in choices.\n"
        "  Difficulty: medium — close enough to make the learner think, not trivial.\n"
        "  Example for abandon (v.): bỏ rơi, từ bỏ | trì hoãn | hoàn thành | thu thập\n"
        "  Example for revenue (n.): doanh thu | chi phí | nhân viên | hợp đồng\n"
        "- answer must equal one choice exactly.\n"
        "- explanationVI: 1 short Vietnamese sentence.\n"
        "- No markdown, no extra keys.\n\n"
        "Words (id|word|pos|vi|en):\n" + "\n".join(lines)
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
        for key in ("items", "data", "results", "questions"):
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
    if not word:
        return None
    prompt = (raw.get("prompt") or "").strip()
    if "nghĩa của từ" not in prompt.lower():
        prompt = f'Nghĩa của từ "{word}" gần nhất với:'
    choices = raw.get("choices") or raw.get("options") or []
    if isinstance(choices, str):
        choices = [c.strip() for c in choices.split("|") if c.strip()]
    choices = [str(c).strip() for c in choices if str(c).strip()]
    # dedupe (casefold for Vietnamese)
    seen = set()
    uniq = []
    for c in choices:
        k = c.casefold()
        if k in seen or k == word.casefold():
            continue
        seen.add(k)
        uniq.append(c)
    choices = uniq[:4]
    if len(choices) < 4:
        return None
    answer = (raw.get("answer") or "").strip()
    if answer not in choices:
        for c in choices:
            if c.casefold() == answer.casefold():
                answer = c
                break
        else:
            # Prefer bank primary VI meaning if model messed up answer pointer.
            bank_m = primary_meaning(vocab_by_id.get(word_id, {}).get("meaning") or "")
            if bank_m and bank_m in choices:
                answer = bank_m
            else:
                answer = choices[0]
    # Always shuffle so correct answer is not stuck at A.
    random.shuffle(choices)
    correct_index = choices.index(answer)
    pos = (vocab_by_id.get(word_id, {}).get("pos") or "Vocab").strip() or "Vocab"
    return {
        "id": f"ai-meaning-{word_id}",
        "wordId": word_id,
        "word": word,
        "type": "meaning",
        "prompt": prompt,
        "choices": choices,
        "correctIndex": correct_index,
        "explanationVI": (raw.get("explanationVI") or raw.get("explanation") or "").strip(),
        "translationVI": "",
        "part": pos if pos != "Word" else "Vocab",
        "source": "ai",
    }


def merge_items(new_items: list[dict]) -> int:
    if not new_items:
        return 0
    with file_lock:
        quiz = load_json(QUIZ_PATH) if QUIZ_PATH.exists() else []
        by_id = {q.get("id"): q for q in quiz if isinstance(q, dict) and q.get("id")}
        word_ids = {int(it["wordId"]) for it in new_items}

        # Drop easy offline meaning-* for these words
        for wid in word_ids:
            by_id.pop(f"meaning-{wid}", None)

        filled = 0
        for it in new_items:
            by_id[it["id"]] = it
            filled += 1

        items = list(by_id.values())

        def sort_key(q: dict):
            qid = str(q.get("id") or "")
            try:
                if qid.startswith("ai-meaning-"):
                    return (0, int(qid.split("-", 2)[2]))
                if qid.startswith("ai-cloze-"):
                    return (1, int(qid.split("-", 2)[2]))
                if qid.startswith("meaning-"):
                    return (2, int(qid.split("-", 1)[1]))
                if qid.startswith("cloze-"):
                    return (3, int(qid.split("-", 1)[1]))
            except Exception:
                pass
            return (9, qid)

        items.sort(key=sort_key)
        save_quiz(items)
    return filled


def main() -> None:
    vocab = load_json(VOCAB_PATH)
    vocab_by_id = {int(r["id"]): r for r in vocab}

    existing = load_json(QUIZ_PATH) if QUIZ_PATH.exists() else []
    # Default: regenerate all meaning items (VI near-miss style).
    # Pass --resume to only fill missing ai-meaning ids.
    force = "--resume" not in sys.argv
    have: set[int] = set()
    if not force:
        for q in existing:
            qid = str(q.get("id") or "")
            if qid.startswith("ai-meaning-"):
                try:
                    have.add(int(qid.split("-", 2)[2]))
                except Exception:
                    pass

    pending = [r for r in vocab if int(r["id"]) not in have]
    print(
        f"proxy={BASE_URL} model={MODEL} force={force}\n"
        f"vocab={len(vocab)} quiz={len(existing)} skip={len(have)} pending={len(pending)}"
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
        items = [n for r in raw if (n := normalize_item(r, vocab_by_id))]
        filled = merge_items(items)
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
                    f"ai_meaning≈{done} ({rate:.1f}/s)",
                    flush=True,
                )
            except Exception as e:
                failed += 1
                print(f"BATCH ERROR: {e}", flush=True)

    quiz = load_json(QUIZ_PATH)
    ai_m = sum(1 for q in quiz if str(q.get("id", "")).startswith("ai-meaning-"))
    easy = sum(1 for q in quiz if str(q.get("id", "")).startswith("meaning-"))
    print(
        f"Done. total={len(quiz)} ai_meaning={ai_m} offline_meaning_left={easy} "
        f"failed={failed} elapsed={time.time()-t0:.0f}s"
    )


if __name__ == "__main__":
    main()
