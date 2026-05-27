# Test Guidance

Read `../docs/engineering/quality-release.md` before adding or changing tests.

- Cover new domain boundaries and public/privacy behavior at the narrowest stable
  layer before adding broad UI verification.
- When a test accompanies API/cloud behavior, load the corresponding native
  Portal or Swift cloud skill.
- Run the focused test target and the verification commands required by the
  affected standard before completing work.
