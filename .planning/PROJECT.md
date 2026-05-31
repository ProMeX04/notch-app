# Notch Portal Migration

## What This Is

This project is a migration of the existing Next.js web portal backend and frontend to a modern, high-performance stack using a Go backend (via Chi & pgx/v5) and a Vite React frontend (via TanStack Router & TypeScript). It aims to transition the portal application to Go + Vite React while maintaining feature parity.

## Core Value

Ensure complete, secure, and reliable authentication, session, payment, capabilities, admin dashboard, and Gemini Live parity on the new Go + Vite React stack to enable seamless user transitions.

## Current Milestone: v2.0 Feature Migration Phase

**Goal:** Migrate payments, pro capabilities, admin dashboard, and Gemini Live APIs from Next.js to Go (Chi + pgx/v5) and Vite React.

**Target features:**
- Payments / VNPay Integration
- Pro Capabilities check and gating
- Admin Dashboard APIs and UI Pages
- Gemini Live APIs and session token orchestration

## Current State

- **Milestone v1.0 (Auth Phase)**: Shipped on 2026-05-31.
  - All email/password authentication, Google OAuth, session audit/revocation backend endpoints and frontend views are migrated and 100% verified.
  - Concurrent development scripts and parity checks are fully functional.

## Requirements

### Validated

#### Milestone v1.0 (Auth Phase)
- ✓ **AUTH-MIG-01**: User can log in with email and password via Go backend (`/api/auth/login`)
- ✓ **AUTH-MIG-02**: User can register a new account via Go backend (`/api/auth/register`)
- ✓ **AUTH-MIG-03**: User can log out and revoke sessions via Go backend (`/api/auth/logout`)
- ✓ **AUTH-MIG-04**: User can view and manage their active sessions/devices via Go backend (`/api/auth/sessions`)
- ✓ **AUTH-MIG-05**: User can authenticate using Google OAuth (Redirect & Callback) via Go backend (`/api/auth/google` and `/api/auth/google/callback`)
- ✓ **AUTH-MIG-06**: System supports Google Drive OAuth integration (exchange, refresh, and handoff) via Go backend (`/api/auth/google-drive/*`)
- ✓ **AUTH-MIG-07**: React Frontend LoginPage integrates with Go backend Login & Google OAuth API
- ✓ **AUTH-MIG-08**: React Frontend AccountPage shows active sessions and handles logout via Go backend APIs
- ✓ **AUTH-MIG-09**: React Frontend OAuth authorization page integrates with Go backend OAuth handlers
- ✓ **AUTH-MIG-10**: Set up concurrent Go backend and Vite React frontend local execution environment
- ✓ **AUTH-MIG-11**: Perform comprehensive auth and session parity verification comparing Next.js and Go + Vite React

### Active (Milestone v2.0)

- [ ] **PAY-MIG-01**: User can create a payment transaction via VNPay integration
- [ ] **PAY-MIG-02**: System handles VNPay IPN callbacks and updates payment transactions status
- [ ] **CAP-MIG-01**: User access is checked and updated dynamically based on active Pro capabilities
- [ ] **ADM-MIG-01**: Admin users can view list of users
- [ ] **ADM-MIG-02**: Admin users can view/edit specific user details and capabilities
- [ ] **ADM-MIG-03**: Admin users can view global stats and Gemini Live model configs
- [ ] **GEM-MIG-01**: Backend supports Gemini Live session token requests and model lists
- [ ] **GEM-MIG-02**: System provides Gemini Live API health status

### Out of Scope

- (None currently)

## Context

The existing system is a Next.js App Router portal backed by PostgreSQL (Prisma). Portions of the Focus and Auth features have already been migrated to Go (internal package) and Vite React. This project completes the migration of all remaining subsystems using Chi for HTTP routing and pgx/v5 for DB interaction.

## Constraints

- **Tech Stack**: Backend must use Go (Chi & pgx/v5); Frontend must use Vite, React, TypeScript, and TanStack Router to match existing half-done implementation.
- **Data Parity**: Session hashes, token formats, and user data must remain fully compatible with the existing Prisma PostgreSQL schema.
- **Port/Coexistence**: The new Go + Vite React environment must run alongside or be easily swappable with Next.js for parity testing.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Focus on Auth Phase | Authentication is the foundation block of the portal; migrating it first allows secure authentication for all subsequent feature migrations. | Shipped in v1.0 |
| Horizontal Layers Strategy | Build out the backend API layers/endpoints in Go first, then wire the React UI pages, and finally test. | Shipped in v1.0 |
| Dual-Server Setup | Run Go backend and Vite React simultaneously to check parity against Next.js. | Shipped in v1.0 |

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
*Last updated: 2026-05-31 after Milestone v2.0 initialization*
