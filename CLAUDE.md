@AGENTS.md

# Claude Code Notes

- Project-specific scoped guidance is under `.claude/rules/`; let matching rules
  load before modifying files in those areas.
- Project skills under `.claude/skills/` are generated mirrors. Update their source
  under `.agent-governance/skills/` and run `node script/agent-governance.mjs sync`.
- `portal/CLAUDE.md` supplies additional Portal-specific instructions when working
  inside `portal/`.
