# API, Data, And Privacy

This standard applies to Portal HTTP contracts and Swift clients that consume
cloud data.

## Authority And Contracts

- Resolve user identity, session identity, owned device identity, entitlements,
  and public visibility from authenticated server state.
- Never let client fields select ownership for user aggregates, rankings, audit
  actors, or paid capabilities.
- Use explicit DTO validation and version durable synchronization contracts when
  the meaning or ownership of persisted aggregates changes.
- In development mode, reject stale schema versions and reset stale local/cloud
  development data. Do not keep compatibility readers for obsolete payloads.
- Design retryable mutations to be idempotent. A cumulative snapshot must merge
  monotonically against server-owned identity.

## Public And Logged Data

- Treat every public response as an allowlist. For leaderboard identities, expose
  the configured public alias or a deliberately masked fallback only.
- Do not sync or expose task titles for aggregate Focus ranking.
- Do not log access/refresh tokens, email values, display-name values, raw private
  payloads, task text, or duration-level focus data.
- Significant mutation success, rejection, and operational failure must emit an
  `AppEvent` with minimal categorized metadata and server-derived actor/device
  fields when available.

## Client Responsibilities

- Cloud-facing Swift features obtain authenticated context through the shared
  Portal subsystem, never by owning duplicate account state.
- Durable offline work remains local and pending after network/auth failure.
- Acknowledgement clears only the exact persisted snapshot sent; concurrent local
  progress remains pending.

## Required Coverage

Contract changes require focused tests for auth, invalid payloads, device/identity
forgery, idempotency or retry semantics, privacy projection, event metadata
exclusion, and date/time boundary logic where applicable.
