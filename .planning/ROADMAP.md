# Roadmap: Notch Portal Migration

## Milestones

- ✅ **v1.0 Auth Phase** — Phases 1-3 (shipped 2026-05-31)
- ✅ **v2.0 Feature Phase** — Phases 4-5 (shipped 2026-05-31)
- 🚧 **v3.0 Integration & Utilities Phase** — Phases 6-8 (in progress)

## Phases

<details>
<summary>✅ v1.0 Auth Phase (Phases 1-3) — SHIPPED 2026-05-31</summary>

- [x] Phase 1: Go Auth Backend APIs — completed 2026-05-31
- [x] Phase 2: React Frontend UI Migration — completed 2026-05-31
- [x] Phase 3: Dual Server Setup & Parity Testing — completed 2026-05-31

</details>

<details>
<summary>✅ v2.0 Feature Phase (Phases 4-5) — SHIPPED 2026-05-31</summary>

- [x] Phase 4: Go Feature Backend APIs — completed 2026-05-31
- [x] Phase 5: React Frontend Features Migration — completed 2026-05-31

</details>

### 🚧 v3.0 Integration & Utilities Phase (In Progress / Planned)

- [ ] **Phase 6: Billing Return Integration** - Implement payment success/failure callback handler and desktop client deep-linking in Vite React.
- [ ] **Phase 7: Utility Pages Migration** - Implement secure downloads page and help center FAQ index in Vite React.
- [ ] **Phase 8: Public Leaderboard Integration** - Implement public active user rankings page in Vite React.

---

## Phase Details

### Phase 6: Billing Return Integration
**Goal**: Implement payment success/failure callback handler and desktop client deep-linking in Vite React.
**Depends on**: Milestone v2.0
**Requirements**: PAY-MIG-04
**Success Criteria** (what must be TRUE):
  1. Navigation to `/billing/vnpay/return` correctly extracts query status parameters from URL.
  2. Secure deep-linking handoff callback triggers automatically to the desktop client.

### Phase 7: Utility Pages Migration
**Goal**: Implement secure downloads page and help center FAQ index in Vite React.
**Depends on**: Phase 6
**Requirements**: UTL-MIG-01, UTL-MIG-02
**Success Criteria** (what must be TRUE):
  1. Downloads page renders installation instructions and secure desktop client download links.
  2. Help center page displays structured FAQ accordion rules.

### Phase 8: Public Leaderboard Integration
**Goal**: Implement public active user rankings page in Vite React.
**Depends on**: Phase 7
**Requirements**: LDB-MIG-01
**Success Criteria** (what must be TRUE):
  1. Leaderboard page fetches rankings list from Go APIs and renders them beautifully.

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Go Auth Backend APIs | v1.0 | 3/3 | Complete | 2026-05-31 |
| 2. React Frontend UI Migration | v1.0 | 2/2 | Complete | 2026-05-31 |
| 3. Dual Server Setup & Parity Testing | v1.0 | 1/1 | Complete | 2026-05-31 |
| 4. Go Feature Backend APIs | v2.0 | 3/3 | Complete | 2026-05-31 |
| 5. React Frontend Features Migration | v2.0 | 2/2 | Complete | 2026-05-31 |
| 6. Billing Return Integration | v3.0 | 0/1 | Not started | - |
| 7. Utility Pages Migration | v3.0 | 0/2 | Not started | - |
| 8. Public Leaderboard Integration | v3.0 | 0/1 | Not started | - |
