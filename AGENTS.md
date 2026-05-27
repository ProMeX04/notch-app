# Notch Engineering Charter

This repository contains the SwiftPM macOS app and its Next.js Portal backend. Read
`docs/architecture.md` and the applicable standard under `docs/engineering/` before
changing a subsystem boundary.

## Non-Negotiable Boundaries

- Keep reusable Swift core targets limited to domain state, events, protocols, and
  deterministic logic. Persistence, networking, authentication, and orchestration
  belong in feature or app infrastructure.
- Shared app infrastructure must use neutral ownership and be injected from
  `Sources/Notch/App/NotchAppEnvironment.swift`. Portal account/auth infrastructure
  belongs in `Sources/Notch/Portal`, not in a consuming feature.
- Store durable sync or outbox data in explicit atomic repositories under
  Application Support, never in `UserDefaults`.
- In Portal, derive identity, device ownership, authorization, and public exposure
  on the server. Routes parse/auth/respond; feature services own business rules.
- Reuse established SwiftUI and Portal UI primitives. New motion must respect
  reduced-motion behavior and must not disturb layout or legibility.
- Significant mutations require privacy-safe observability and focused tests.

## Standards And Skills

- Architecture: `docs/engineering/architecture-boundaries.md`
- API, data, and privacy: `docs/engineering/api-data-privacy.md`
- Swift UI: `docs/engineering/swift-ui-patterns.md`
- Portal UI: `docs/engineering/portal-ui-patterns.md`
- Verification and release: `docs/engineering/quality-release.md`

Load the relevant native skill before work in its scope:

- Portal API/data/privacy: `notch-portal-api-conventions`
- Swift Portal/cloud sync: `notch-swift-cloud-api-conventions`
- SwiftUI/AppKit presentation: `notch-swift-ui-conventions`
- Portal React/Next.js presentation: `notch-portal-ui-conventions`
- Build, schema reset, deploy, or release: `notch-verification-release`

Skills are authored under `.agent-governance/skills/` and mirrored into the native
agent directories by `node script/agent-governance.mjs sync`. Do not edit mirrored
copies in `.codex/skills/`, `.claude/skills/`, or `.agents/skills/` directly.
This repository is in development mode: governance baseline allowances are not
permitted. If `node script/agent-governance.mjs check` reports existing
architecture debt, fix or move the code to the correct owner before marking work
complete.
Development-mode persisted data changes are clean breaks: reset stale dev data
and reject stale payload versions instead of adding legacy fallback or data-shim
branches. Only add compatibility code when the user explicitly says production
data must be retained.

## Required Verification

- Run `node script/agent-governance.mjs check` when changing architecture,
  instructions, standards, skills, or validation tooling.
- For Swift changes, run the focused suite plus `swift build`; use
  `./script/build_and_run.sh --verify` for app startup or integration wiring.
- For Portal changes, run relevant tests plus `npm run lint` and `npm run build`
  from `portal/`.
- Schema, production data, or deployment changes require an explicit rollout,
  acceptance check, and rollback note.
