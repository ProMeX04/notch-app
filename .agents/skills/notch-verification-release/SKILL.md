---
name: notch-verification-release
description: Verify, deploy, and release Notch changes with explicit evidence and rollback awareness. Use when completing substantial code changes, changing persisted contracts, deploying the Portal to Vercel, packaging/installing the macOS app, resetting data, or preparing a release.
---

# Notch Verification And Release

Read `docs/engineering/quality-release.md` and identify every affected surface
before declaring a task complete or performing a deployment.

## Verification

- For governance changes, run `node script/agent-governance.mjs check` and its
  validator tests.
- For Swift code, run focused tests, `swift test`, and `swift build`; run
  `swift run NotchFocusTests` for Focus.
- For integration/startup wiring, run `./script/build_and_run.sh --verify`.
- For Portal code, run relevant tests, `npm run lint`, and `npm run build` in
  `portal/`.

## Persistent Contracts And Deployment

- In development mode, use reset policy for changed persisted contracts. Do not
  add legacy data-shim/fallback readers unless the user explicitly requires
  production data retention.
- Deploy server compatibility before distributing a client that depends on it.
- Verify the production user flow and privacy/event outcomes after deployment.
- Record rollback implications and any intentional remaining cleanup.

## Completion Report

Report behavior changed, commands actually run, warnings or unrun checks,
reset/data actions, deployment target when applicable, and deferred debt.
