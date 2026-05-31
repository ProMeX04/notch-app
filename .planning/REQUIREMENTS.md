# Requirements: Notch Portal Migration - Integration & Utilities Phase (Milestone v3.0)

**Defined:** 2026-05-31
**Core Value:** Complete the migration of payment return workflows, utility pages (downloads, help), and public leaderboards to Go + React.

## v1 Requirements

Requirements for this milestone release. Each maps to roadmap phases.

### Payments & billing (PAY)

- [ ] **PAY-MIG-04**: React Frontend payment return page (`/billing/vnpay/return`) parses query parameters, displays payment outcome (Success/Failure), and handles deep-link redirection back to the desktop application.

### Utility Pages (UTL)

- [ ] **UTL-MIG-01**: React Frontend Downloads page (`/downloads`) provides secure client download links and installation instructions.
- [ ] **UTL-MIG-02**: React Frontend Help center page (`/help`) renders the FAQ directory and support links.

### Leaderboards (LDB)

- [ ] **LDB-MIG-01**: React Frontend Leaderboard page (`/leaderboard`) fetches active user rankings from Go backend API.

## Out of Scope

- Live WebSocket audio streaming in Go backend — Deferred to subsequent milestones.
- Subscription billing support (recurring cards) — Deferred.

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PAY-MIG-04 | Phase 6 | Pending |
| UTL-MIG-01 | Phase 7 | Pending |
| UTL-MIG-02 | Phase 7 | Pending |
| LDB-MIG-01 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 4 total
- Mapped to phases: 4
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-31*
*Last updated: 2026-05-31 after Milestone v3.0 definition*
