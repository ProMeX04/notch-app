---
name: notch-portal-api-conventions
description: Maintain HTTP API contracts and server-side boundaries in the Notch Next.js portal. Use when adding, changing, debugging, or reviewing routes under portal/src/app/api, portal API service/lib code, Prisma-backed endpoint behavior, authentication/device ownership, public data exposure, mutation event logging, or UI consuming a portal API contract.
---

# Notch Portal API Conventions

Apply this workflow to Portal API work. If a change also modifies the macOS
client contract or sync behavior, load `notch-swift-cloud-api-conventions`.

## Read First

1. Read `portal/AGENTS.md` and `docs/engineering/api-data-privacy.md`.
2. Read relevant Next.js documentation under `portal/node_modules/next/dist/docs/`
   before changing App Router behavior.
3. Inspect the nearest route, feature service/lib, auth helper, event logger,
   Prisma schema, and tests.
4. Classify the endpoint: public or authenticated; read or mutation;
   device-bound or not; privacy-sensitive or not.

## Required Boundary

- Keep route handlers limited to request parsing, authentication/authorization,
  service invocation, event emission, and HTTP responses.
- Keep validation, aggregate rules, idempotency, ranking calculations, and
  database behavior in feature `src/lib` or service modules.
- Keep Prisma access outside UI pages. UI consumes a contract and must not
  reproduce authorization or ranking rules.
- Extend existing feature modules before creating a generic abstraction.

## Identity And Privacy

- Derive `userId`, session identity, device ownership, permissions, and public
  visibility on the server.
- Never accept client fields as ownership selectors for user aggregates, ranking,
  entitlements, sessions, or audit identity.
- Treat public response fields as an allowlist. Do not expose private name, email,
  or device data through accidental fallbacks.
- Do not log tokens, raw private payloads, email/display-name values, task
  content, or duration-level details in event metadata.

## Contracts And Mutations

- Use explicit DTO validation, including valid calendar dates and numeric bounds.
- Version durable sync payloads when ownership or aggregate meaning changes;
  reject incompatible writers instead of accepting old shapes.
- During development, reset stale data and remove obsolete readers instead of
  adding compatibility branches.
- Make retries idempotent and merge cumulative snapshots only against
  server-owned identity.
- Log meaningful mutation success, rejection, and failure through `AppEvent` with
  minimal categorized metadata.

## Verification

Cover relevant auth, validation/version, forged ownership, idempotency, privacy,
event-metadata, and time-boundary cases. Run from `portal/`:

```bash
npm run test:focus
npm run lint
npm run build
```

For Focus ranking, inspect `src/app/api/focus/sync/route.ts`,
`src/lib/focus-ranking.ts`, and their focused tests before editing.
