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

## Milestone: v3.0 — Integration & Utilities Phase

**Shipped:** 2026-05-31
**Phases:** 3 | **Plans:** 4 | **Sessions:** 2

### What Was Built
- VNPay payment return page (`/billing/vnpay/return`) parsing query params, displaying outcome, and deep-linking back to desktop via `notch://visibility/show`
- Downloads page (`/downloads`) with DMG download card, Chrome extension card, and Gatekeeper security instructions
- Help/FAQ center (`/help`) with interactive accordion FAQ sections and support links
- Public Leaderboard page (`/leaderboard`) with podium (top 3), animated rank table (4-50), window switcher (week/all-time), loading/empty/error states

### What Worked
- The `--skip-ui` plan-phase flag enabled fully automated planning and execution with zero blocking prompts.
- Existing Go backend leaderboard endpoint (`GET /api/focus/leaderboard`) was already complete — Phase 8 was purely frontend work.
- Dropping Supabase realtime from the leaderboard (Next.js used it) in favor of standard `useQuery` with tab-switch refetch simplified the implementation with no user-facing regression.

### What Was Inefficient
- Duplicate `style` JSX attribute on `<li>` row required a small post-implementation fix — avoidable by merging style objects upfront.
- Phase SUMMARY.md files were not written during this milestone (gsd-tools showed 0 summaries), which reduced MILESTONES.md accomplishment extraction quality.

### Patterns Established
- Local `useState` for tab switcher (not URL-based navigation) for instant UX without browser history pollution.
- Inline styles with inline `<style>` tag for CSS animations (e.g., spinner) when CSS modules are unavailable — acceptable for isolated single-use animations.
- Lucide icon mocking pattern in Vitest: `vi.mock('lucide-react', () => ({ Trophy: () => <span data-testid="..." /> }))` for deterministic test assertions.

### Key Lessons
- Always export shared types (e.g., `LeaderboardEntry`) from the component file so test files can import and reuse them without duplicating type definitions.
- When migrating a Next.js component, audit every import for framework-specific APIs (`next/link`, `next/navigation`, Supabase client) and replace with Vite-native equivalents before implementing logic.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 4 | 3 | Initial auth foundations and automated API parity comparisons. |
| v2.0 | 3 | 2 | Gated dashboard screens, dynamic capability policies, and external VNPay gateways. |
| v3.0 | 2 | 3 | Utility pages and leaderboard wireup; fully automated --skip-ui planning pipeline. |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 18 | 90% | Zero-debt enforcement passed |
| v2.0 | 25 | 92% | Zero-debt enforcement passed |
| v3.0 | 10 | 93% | Zero-debt enforcement passed |
