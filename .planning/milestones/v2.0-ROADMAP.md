# Roadmap: Notch Portal Migration - Feature Phase (Milestone v2.0)

## Overview

This roadmap lays out the path to migrate the Payments (VNPay), Capabilities Gating, Admin Dashboard, and Gemini Live token APIs of the Notch Portal from Next.js to Go (Chi + pgx/v5) and Vite React.

## Phases

- [x] **Phase 4: Go Feature Backend APIs** - Implement all payment, capabilities, admin dashboard, and Gemini Live API endpoints in Go.
- [x] **Phase 5: React Frontend Features Migration** - Connect React views in `portal/web` to the new Go feature APIs. (completed 2026-05-31)

## Phase Details

### Phase 4: Go Feature Backend APIs

**Goal**: Implement all payment, capabilities, admin dashboard, and Gemini Live API endpoints in Go.
**Depends on**: Nothing
**Requirements**: PAY-01, PAY-02, CAP-01, CAP-03, ADM-01, ADM-02, ADM-03, GEM-01, GEM-02
**Success Criteria** (what must be TRUE):

  1. Payment creation endpoint (`POST /api/payments/vnpay/create`) creates signed checkout URLs.
  2. VNPay IPN handler processes callbacks, verifies signatures, and updates user Pro statuses.
  3. Capabilities endpoint (`GET /api/capabilities`) projects public capability states.
  4. Admin dashboard routes (capabilities list, overrides, restoration, user list/edit) are operational and authorized.
  5. Gemini Live token generation (`POST /api/gemini-live/token`) verifies user Pro entitlement.

**Plans**: 3 plans

Plans:

- [x] 04-01: Implement VNPay payment creation, IPN, and return handler endpoints
- [x] 04-02: Implement Capabilities projection, policies, and Admin capability management
- [x] 04-03: Implement Admin User management and Gemini Live token orchestration

### Phase 5: React Frontend Features Migration

**Goal**: Connect React views in `portal/web` to the new Go feature APIs.
**Depends on**: Phase 4
**Requirements**: PAY-03, CAP-02, ADM-04
**Success Criteria** (what must be TRUE):

  1. Profile upgrade triggers redirect to VNPay interface.
  2. Pricing/landing pages adapt layouts dynamically based on capability policies.
  3. Admin console lists capabilities, handles overrides, lists users, and edits capabilities.

**Plans**: 2 plans

Plans:

- [ ] 05-01: Connect Profile Upgrade payments and Capabilities pricing UI in React
- [ ] 05-02: Connect Admin Capabilities and User Management console views in React

## Progress

**Execution Order:**
Phases execute in numeric order: 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Go Feature Backend APIs | 3/3 | Completed | 2026-05-31 |
| 5. React Frontend Features Migration | 0/1 | Complete    | 2026-05-31 |
