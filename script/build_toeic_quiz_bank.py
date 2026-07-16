#!/usr/bin/env python3
"""Build offline TOEIC multiple-choice quiz bank from vocabulary.

Input:  Sources/Notch/Resources/TOEIC/toeic_vocabulary.json
Output: Sources/Notch/Resources/TOEIC/toeic_quiz.json

For each word produces:
  1) cloze item  — blank the headword in its example sentence
  2) meaning item — "Nghĩa của từ X là gì?" with 4 VI meaning choices

No runtime AI — pure offline generation.
"""

from __future__ import annotations

import json
import random
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOCAB_PATH = ROOT / "Sources/Notch/Resources/TOEIC/toeic_vocabulary.json"
OUT_PATH = ROOT / "Sources/Notch/Resources/TOEIC/toeic_quiz.json"

RNG = random.Random(42)


def primary_pos(pos: str) -> str:
    p = (pos or "").strip().lower()
    if not p or p == "word":
        return "other"
    # "v., n." → first tag
    first = p.split(",")[0].strip().rstrip(".")
    return first or "other"


def primary_meaning_vi(meaning: str) -> str:
    """Take first sense group, strip POS label."""
    m = (meaning or "").strip()
    if not m:
        return ""
    # "(v.) bỏ rơi, từ bỏ; (n.) …" → first segment before ;
    first = m.split(";")[0].strip()
    first = re.sub(r"^\([^)]+\)\s*", "", first).strip()
    return first or m


def blank_example(example: str, word: str) -> str | None:
    ex = (example or "").strip()
    w = (word or "").strip()
    if not ex or not w:
        return None
    # whole-word, case-insensitive, first occurrence
    pattern = re.compile(rf"\b{re.escape(w)}\b", re.IGNORECASE)
    if not pattern.search(ex):
        # try without word-boundary (hyphenated / plural-ish)
        pattern = re.compile(re.escape(w), re.IGNORECASE)
        if not pattern.search(ex):
            return None
    return pattern.sub("_____", ex, count=1)


def pick_distractor_words(word: str, pos_key: str, by_pos: dict[str, list[dict]], k: int = 3) -> list[str]:
    pool = [r["word"] for r in by_pos.get(pos_key, []) if r["word"].lower() != word.lower()]
    if len(pool) < k:
        # fallback: any words
        all_words = []
        for rows in by_pos.values():
            all_words.extend(r["word"] for r in rows if r["word"].lower() != word.lower())
        pool = list(dict.fromkeys(pool + all_words))
    RNG.shuffle(pool)
    return pool[:k]


def pick_distractor_meanings(correct: str, all_meanings: list[str], k: int = 3) -> list[str]:
    c = correct.lower()
    pool = [m for m in all_meanings if m and m.lower() != c]
    # prefer similar length
    pool.sort(key=lambda m: abs(len(m) - len(correct)))
    # shuffle among closest 40 then take k
    close = pool[: max(40, k * 8)]
    RNG.shuffle(close)
    out = []
    seen = {c}
    for m in close:
        key = m.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(m)
        if len(out) >= k:
            break
    placeholders = ["(không đúng)", "(nghĩa khác)", "(không phải)"]
    for p in placeholders:
        if len(out) >= k:
            break
        if p.lower() not in seen:
            out.append(p)
            seen.add(p.lower())
    return out[:k]


def main() -> None:
    vocab: list[dict] = json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
    by_pos: dict[str, list[dict]] = defaultdict(list)
    meanings: list[str] = []
    for row in vocab:
        by_pos[primary_pos(row.get("pos") or "")].append(row)
        pm = primary_meaning_vi(row.get("meaning") or "")
        if pm:
            meanings.append(pm)

    quizzes: list[dict] = []
    cloze_n = 0
    meaning_n = 0

    for row in vocab:
        wid = int(row["id"])
        word = (row.get("word") or "").strip()
        if not word or len(word) <= 1:
            continue
        pos = (row.get("pos") or "").strip() or "Word"
        pos_key = primary_pos(pos)
        meaning = primary_meaning_vi(row.get("meaning") or "")
        example = (row.get("example") or "").strip()
        example_vn = (row.get("example_vn") or "").strip()
        phonetic = (row.get("pronunciation") or "").strip()

        # --- Cloze quiz ---
        prompt = blank_example(example, word)
        if prompt and "_____" in prompt:
            distractors = pick_distractor_words(word, pos_key, by_pos, 3)
            if len(distractors) >= 3:
                choices = [word] + distractors
                RNG.shuffle(choices)
                correct_index = choices.index(word)
                explanation = (
                    f"Đáp án \"{word}\" ({pos}). "
                    + (f"Nghĩa: {meaning}." if meaning else "")
                ).strip()
                quizzes.append(
                    {
                        "id": f"cloze-{wid}",
                        "wordId": wid,
                        "word": word,
                        "type": "cloze",
                        "prompt": prompt,
                        "choices": choices,
                        "correctIndex": correct_index,
                        "explanationVI": explanation,
                        "translationVI": example_vn,
                        "part": pos if pos != "Word" else "Vocab",
                    }
                )
                cloze_n += 1

        # --- Meaning quiz ---
        if meaning:
            wrong = pick_distractor_meanings(meaning, meanings, 3)
            if len(wrong) >= 3:
                choices = [meaning] + wrong
                RNG.shuffle(choices)
                correct_index = choices.index(meaning)
                if phonetic:
                    mprompt = f'Nghĩa của từ "{word}" (/{phonetic.strip("/")}/) là gì?'
                else:
                    mprompt = f'Nghĩa của từ "{word}" là gì?'
                quizzes.append(
                    {
                        "id": f"meaning-{wid}",
                        "wordId": wid,
                        "word": word,
                        "type": "meaning",
                        "prompt": mprompt,
                        "choices": choices,
                        "correctIndex": correct_index,
                        "explanationVI": f'Từ "{word}" ({pos}) có nghĩa: {meaning}.',
                        "translationVI": "",
                        "part": pos if pos != "Word" else "Vocab",
                    }
                )
                meaning_n += 1

    OUT_PATH.write_text(
        json.dumps(quizzes, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {len(quizzes)} items → {OUT_PATH}\n"
        f"  cloze={cloze_n} meaning={meaning_n} vocab={len(vocab)}"
    )


if __name__ == "__main__":
    main()
