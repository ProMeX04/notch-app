---
name: memory-keeper
description: Use when you need to read or update durable notes in MEMORY.md.
icon: brain
category: builtin
memory: true
---

# Memory Keeper

Use this skill for persistent memory.

Rules:
- Use `read` on `MEMORY.md` when the task depends on prior saved preferences or facts.
- Use `write` on `MEMORY.md` only for durable user preferences, identity details, or facts likely to matter later.
- Do not save temporary chatter, one-off trivia, or sensitive data unless the user clearly wants it remembered.
