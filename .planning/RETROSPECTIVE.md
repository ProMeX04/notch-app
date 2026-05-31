# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — Feature Phase

**Shipped:** 2026-05-31
**Phases:** 2 | **Plans:** 2 | **Sessions:** 3

### What Was Built
- VNPay payments integration (signed checkout URL generation, signature validation return/IPN handlers)
- Capabilities policies engine (merging config manifest defaults with database overrides)
- Admin console console dashboards (capabilities configurator table, paginated users database, user details summary sessions/payments/events view)
- Gemini Live token session generation and allowed models syncer

### What Worked
- Completing backend Chi handlers first, then migrating frontend views worked incredibly well for isolating logic and API contracts.
- Automated testing (Go tests, Vitest) validated code logic instantly at each phase boundary.

### What Was Inefficient
- React inline style shortcuts (`h`, `w`) caused build time compile errors that were only caught at production build compilation check.

### Patterns Established
- Gating administrative layout routes at parent router components via user role checking flags.
- Timing-safe HMAC-SHA512 checksum validation routines for third-party billing providers.

### Key Lessons
- Always run the production build compiles (`npm run build` / `tsc`) regularly in React projects using strict TypeScript configurations to detect styling shorthand type mismatches early.

---

## Milestone: v1.0 — Auth Phase

**Shipped:** 2026-05-31
**Phases:** 3 | **Plans:** 6 | **Sessions:** 4

### What Was Built
- Email/password authentication login, register, logout handlers
- Google OAuth and Google Drive oauth handoffs
- React frontend login views, auth provider, and Account Page sessions management view
- Parity testing script comparing Next.js endpoints output to new Go backend API responses

### What Worked
- Parallel server setup (`dev-migrated.sh` mounting Go backend and Vite React frontend) enabled fast iterations.
- Parity test suite compared exact JSON structures, headers, and codes to prevent regressions.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 4 | 3 | Initial auth foundations and automated API parity comparisons. |
| v2.0 | 3 | 2 | Gated dashboard screens, dynamic capability policies, and external VNPay gateways. |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 18 | 90% | Zero-debt enforcement passed |
| v2.0 | 25 | 92% | Zero-debt enforcement passed |
