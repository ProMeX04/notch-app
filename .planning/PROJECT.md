# Notch Portal Migration

## What This Is

A complete migration of the existing Next.js web portal backend and frontend to a modern, high-performance stack using a Go backend (via Chi & pgx/v5) and a Vite React frontend (via TanStack Router & TypeScript). The portal application is now fully running on Go + Vite React with feature parity for all shipped subsystems.

## Core Value

Ensure complete, secure, and reliable authentication, session, payment, capabilities, admin dashboard, Gemini Live, utility pages, and public leaderboard parity on the new Go + Vite React stack to enable seamless user transitions away from Next.js.

## Current State

All 3 milestones shipped as of 2026-05-31. The Notch Portal Migration project is **feature-complete** for the originally scoped subsystems:

- **v1.0 Auth Phase** — Email/password auth, Google OAuth, session management fully migrated.
- **v2.0 Feature Phase** — VNPay payments, capabilities gating, admin dashboard, Gemini Live APIs fully migrated.
- **v3.0 Integration & Utilities Phase** — Billing return handler, Downloads page, Help/FAQ center, and Public Leaderboard page fully migrated.

The Go backend (`portal/api/`) and Vite React frontend (`portal/web/`) are now the primary serving stack.

## Requirements

### Validated

#### Milestone v1.0 (Auth Phase)
- ✓ **AUTH-MIG-01**: User can log in with email and password via Go backend (`/api/auth/login`) — v1.0
- ✓ **AUTH-MIG-02**: User can register a new account via Go backend (`/api/auth/register`) — v1.0
- ✓ **AUTH-MIG-03**: User can log out and revoke sessions via Go backend (`/api/auth/logout`) — v1.0
- ✓ **AUTH-MIG-04**: User can view and manage their active sessions/devices via Go backend (`/api/auth/sessions`) — v1.0
- ✓ **AUTH-MIG-05**: User can authenticate using Google OAuth (Redirect & Callback) via Go backend — v1.0
- ✓ **AUTH-MIG-06**: System supports Google Drive OAuth integration (exchange, refresh, and handoff) — v1.0
- ✓ **AUTH-MIG-07**: React Frontend LoginPage integrates with Go backend Login & Google OAuth API — v1.0
- ✓ **AUTH-MIG-08**: React Frontend AccountPage shows active sessions and handles logout — v1.0
- ✓ **AUTH-MIG-09**: React Frontend OAuth authorization page integrates with Go backend OAuth handlers — v1.0
- ✓ **AUTH-MIG-10**: Set up concurrent Go backend and Vite React frontend local execution environment — v1.0
- ✓ **AUTH-MIG-11**: Comprehensive auth and session parity verification comparing Next.js and Go + Vite React — v1.0

#### Milestone v2.0 (Feature Phase)
- ✓ **PAY-MIG-01**: User can create a payment transaction via VNPay integration — v2.0
- ✓ **PAY-MIG-02**: System handles VNPay IPN callbacks and updates payment transaction status — v2.0
- ✓ **CAP-MIG-01**: User access is checked and updated dynamically based on active Pro capabilities — v2.0
- ✓ **ADM-MIG-01**: Admin users can view list of users — v2.0
- ✓ **ADM-MIG-02**: Admin users can view/edit specific user details and capabilities — v2.0
- ✓ **ADM-MIG-03**: Admin users can view global stats and Gemini Live model configs — v2.0
- ✓ **GEM-MIG-01**: Backend supports Gemini Live session token requests and model lists — v2.0
- ✓ **GEM-MIG-02**: System provides Gemini Live API health status — v2.0

#### Milestone v3.0 (Integration & Utilities Phase)
- ✓ **PAY-MIG-04**: React Frontend payment return page (`/billing/vnpay/return`) parses query parameters, displays payment outcome, and handles deep-link redirection back to the desktop application — v3.0
- ✓ **UTL-MIG-01**: React Frontend Downloads page (`/downloads`) provides secure client download links and installation instructions — v3.0
- ✓ **UTL-MIG-02**: React Frontend Help center page (`/help`) renders the FAQ directory and support links — v3.0
- ✓ **LDB-MIG-01**: React Frontend Leaderboard page (`/leaderboard`) fetches active user rankings from Go backend API — v3.0

### Active

*(No active requirements — all scoped features shipped. Next milestone TBD.)*

### Out of Scope

- Live WebSocket audio streaming in Go backend — Deferred to subsequent milestones.
- Subscription billing support (recurring cards) — Deferred.

## Context

The existing system was a Next.js App Router portal backed by PostgreSQL (Prisma). The migration is now complete across all originally scoped subsystems. The Go + Vite React stack runs concurrently with Next.js via `dev-migrated.sh` for parity testing.

**Stack:** Go 1.23 (Chi + pgx/v5) backend · Vite React (TanStack Router + TypeScript) frontend.
**DB:** PostgreSQL (Prisma schema, accessed via pgx raw SQL from Go).
**Deployment target:** Vercel (Next.js), with Go binary deployed separately.

## Constraints

- **Tech Stack**: Backend must use Go (Chi & pgx/v5); Frontend must use Vite, React, TypeScript, and TanStack Router.
- **Data Parity**: Session hashes, token formats, and user data must remain fully compatible with the existing Prisma PostgreSQL schema.
- **Port/Coexistence**: The new Go + Vite React environment must run alongside or be easily swappable with Next.js for parity testing.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------| 
| Focus on Auth Phase first | Authentication is the foundation block; migrating it first allows secure auth for all subsequent feature migrations. | ✓ Shipped v1.0 |
| Horizontal Layers Strategy | Build Go API layers first, then wire React UI pages, then test — maximizes parallel execution. | ✓ Shipped v1.0–v3.0 |
| Dual-Server Setup | Run Go backend and Vite React simultaneously to check parity against Next.js. | ✓ Shipped v1.0 |
| HMAC-SHA512 Webhook Auth | VNPay signature verification requires timing-safe HMAC-SHA512 parsing. | ✓ Shipped v2.0 |
| Capabilities Policies Merge | Merging manifest defaults with user database overrides avoids full schema coupling. | ✓ Shipped v2.0 |
| Dynamic Gemini Live Syncer | Syncing allowed models directly from Google APIs dynamically. | ✓ Shipped v2.0 |
| No Supabase in Vite | Next.js used Supabase realtime on leaderboard; Vite uses standard `useQuery` with tab-switch refetch — simpler, no extra dependency. | ✓ Shipped v3.0 |
| Window state (not router) for leaderboard tabs | Tab switching is local `useState` for instant UX without browser history pollution. | ✓ Shipped v3.0 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-31 after Milestone v3.0 completion — project feature-complete*
