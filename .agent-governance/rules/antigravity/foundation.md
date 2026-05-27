# Notch Engineering Foundation

Apply this rule for all workspace work.

- Read `AGENTS.md` before making changes and read the applicable standard under
  `docs/engineering/`.
- Treat `.agent-governance/skills/` as source and `.agents/skills/` as generated
  native mirrors; never update only a mirror.
- Run `node script/agent-governance.mjs check` when changing standards, rules,
  skills, or their generator.
