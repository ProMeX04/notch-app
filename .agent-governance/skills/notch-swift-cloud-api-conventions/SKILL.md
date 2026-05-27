---
name: notch-swift-cloud-api-conventions
description: Maintain cloud-facing Swift architecture and API contracts in the Notch macOS app. Use when adding, changing, debugging, or reviewing Sources/Notch/Portal, feature cloud sync/coordinators/repositories, URLSession clients, authenticated Portal context, durable outboxes, Codable API DTOs, or core events that feed cloud behavior.
---

# Notch Swift Cloud API Conventions

Apply this workflow to cloud-facing app work. If a change modifies the Portal
endpoint or server contract, load `notch-portal-api-conventions`.

## Read First

1. Read `AGENTS.md`, `docs/engineering/architecture-boundaries.md`, and
   `docs/engineering/api-data-privacy.md`.
2. Inspect `Sources/Notch/App/NotchAppEnvironment.swift`, the owning feature
   coordinator/repository, `Sources/Notch/Portal`, relevant domain event, and
   adjacent tests.
3. Identify whether the boundary is domain event, persistence/outbox,
   authenticated transport, orchestration, or UI state.

## Required Boundary

- Keep core targets pure: domain state, events, protocols, and deterministic
  logic only.
- Put shared Portal configuration, session/device context, refresh, and account
  coordination in `Sources/Notch/Portal`.
- Put feature-specific HTTP behavior and persistence in its consuming feature.
- Own long-lived dependencies once in `NotchAppEnvironment` and inject them.
- Keep Account/global UI bound to Portal state, not feature-mirrored login state.

## Sync And Persistence

- Use distinct domain events for distinct product meanings; do not infer
  completed sessions from duration flushes or UI transitions.
- Split time-derived aggregates at the server-contract boundary, currently UTC
  days for Focus ranking.
- Store pending sync through an atomic feature repository under Application
  Support, never `UserDefaults`.
- Send retryable cumulative snapshots and acknowledge only the snapshot sent.
- Keep signed-out and offline local behavior functional without dropping pending
  durable progress.

## Transport And Privacy

- Obtain authentication through `PortalAccountCoordinator` or a narrow injected
  protocol; do not read tokens from feature view models.
- Use explicit `Codable` DTOs matching server versions and field naming.
- Do not send task titles or client-selected ranking identity fields.
- Treat `401` as a soft sync failure unless shared account infrastructure decides
  the session must be cleared.
- During development, reset stale local sync state when contracts change. Do not
  add legacy decoders or fallback readers for obsolete local payloads.

## Verification

Cover domain-event meaning, UTC aggregation, persistence/reload, failed and
concurrent acknowledgement, signed-out behavior, profile mutation, and
composition integration. Run:

```bash
swift test
swift run NotchFocusTests
swift build
```

Use `./script/build_and_run.sh --verify` when app startup or production wiring
changes.
