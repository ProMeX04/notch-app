# Quality And Release

This standard defines completion evidence for engineering work and deployment.

## Verification Matrix

| Change area | Required checks |
| --- | --- |
| Governance, rules, or skills | `node script/agent-governance.mjs check`; validator tests |
| Swift domain/app code | Focused tests, `swift test`, `swift build` |
| Focus app behavior | `swift run NotchFocusTests` |
| Startup/integration wiring | `./script/build_and_run.sh --verify` |
| Portal API/UI | Relevant Node tests, `npm run lint`, `npm run build` |
| Focus Portal behavior | `npm run test:focus` |
| Gemini Portal behavior | `npm run test:gemini-live` |

CI runs the governance check and the complete Swift and Portal matrix for every
pull request and push. Local targeted checks do not replace CI evidence.

## Data And Deployment

- In development mode, schema or persisted-contract changes must prefer reset and
  clean replacement over compatibility branches. Do not add legacy readers,
  data shims, or old-client fallback code unless the user explicitly marks
  the data as production-retained.
- Deploy Portal before distributing a client that depends on a new server
  contract. Reject incompatible writers instead of silently accepting old shapes.
- Production acceptance must verify the affected user flow, relevant server data
  or events without exposing secrets, and public/privacy behavior where relevant.

## Delivery Notes

An agent completion report must state changed behavior, commands actually run,
known warnings or unrun checks, reset/data actions, deployment URL when deployed,
and any follow-up debt intentionally left in backlog.
