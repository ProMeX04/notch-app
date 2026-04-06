---
name: memory-keeper
description: Use when you need to read or update durable notes in MEMORY.md or stable user profile details in USER.md.
icon: brain
category: builtin
memory: true
---

# Memory Keeper

Use this skill for persistent memory and user profile storage.

Rules:
- Use `read` on `USER.md` for stable user identity details such as name, nickname, pronouns, role, bio, or response preferences.
- Use `read` on `MEMORY.md` for durable facts, preferences, habits, and other context that may matter later.
- Use `write` on `USER.md` when the user shares or corrects who they are, such as "my name is...", "call me...", or similar profile details.
- Use `write` on `MEMORY.md` for durable preferences, long-term context, or facts likely to matter later that are not core profile fields.
- When the user explicitly asks you to remember their name or identity, update `USER.md`, not just `MEMORY.md`.
- Prefer keeping core profile facts in `USER.md` and broader long-term notes in `MEMORY.md`.
- Do not save temporary chatter, one-off trivia, or sensitive data unless the user clearly wants it remembered.
