## Project

**Notch Portal Migration - Auth Phase**

This project is a migration of the existing Next.js web portal backend and frontend to a modern, high-performance stack using a Go backend (via Chi & pgx/v5) and a Vite React frontend (via TanStack Router & TypeScript). It aims to transition the portal application to Go + Vite React while maintaining feature parity.

**Core Value:** Ensure complete, secure, and reliable authentication and session parity on the new Go + Vite React stack to enable seamless user transitions.

### Constraints

- **Tech Stack**: Backend must use Go (Chi & pgx/v5); Frontend must use Vite, React, TypeScript, and TanStack Router to match existing half-done implementation.
- **Data Parity**: Session hashes, token formats, and user data must remain fully compatible with the existing Prisma PostgreSQL schema.
- **Port/Coexistence**: The new Go + Vite React environment must run alongside or be easily swappable with Next.js for parity testing.

## Technology Stack

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Go | 1.23.0+ | Backend language | High performance, single binary deployment, minimal runtime overhead. |
| Chi Router | v5.2.3 | HTTP Router | Lightweight, idiomatic Go router with middleware support; already in project. |
| pgx/v5 | v5.7.6 | PostgreSQL Driver | Standard low-level PostgreSQL driver, supports connection pooling. |
| React | v18.0+ | UI Library | Component-driven UI framework, standard for Vite apps. |
| TanStack Router | v1.0+ | Frontend Routing | Type-safe React router; matches existing half-done app. |
| TypeScript | v5.0+ | Typing | Strict typing for both backend integration and component props. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| golang.org/x/crypto | - | Hashing passwords | Used for BCrypt password hashing. |
| go-chi/cors | v1.2.2 | CORS Middleware | To allow request sharing from the dev frontend server to Go backend. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Air | Hot reloading for Go | Auto-rebuilds and restarts the backend during development. |
| Vite | Frontend tooling | Offers fast HMR (Hot Module Replacement) and bundling. |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Chi | Gin / Echo | Gin/Echo provide more built-in features, but Chi is lightweight and already chosen. |
| pgx/v5 | GORM | GORM is useful for automatic table migrations, but raw SQL via pgx provides better performance and schema control. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Next.js App Router | High memory usage, complex build times, slow cold starts. | Vite React + Go backend |
| Prisma | Heavy Node.js dependency, runtime overhead. | pgx / pgxpool in Go |

## Stack Patterns by Variant

- Use Go `golang.org/x/oauth2`
- Because it handles OAuth2 redirect, state checking, and token exchange.
- Use DB-backed sessions with Token hashing (SHA-256)
- Because it is highly secure and allows revoking active sessions instantly.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Go 1.23.0 | pgx/v5.7.6 | fully compatible. |

## Sources

- [Go-Chi Official Docs](https://github.com/go-chi/chi) — Chi routing pattern.
- [pgx Official Docs](https://github.com/jackc/pgx) — Connection pooling guide.

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.

## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| notch-portal-api-conventions | Maintain HTTP API contracts and server-side boundaries in the Notch Next.js portal. Use when adding, changing, debugging, or reviewing routes under portal/src/app/api, portal API service/lib code, Prisma-backed endpoint behavior, authentication/device ownership, public data exposure, mutation event logging, or UI consuming a portal API contract. | `.agents/skills/notch-portal-api-conventions/SKILL.md` |
| notch-portal-ui-conventions | Build and review polished, consistent Portal interfaces in Notch. Use when changing Next.js pages, React components, CSS, layouts, public leaderboard or account experiences, admin screens, responsive behavior, motion, loading/error states, or accessibility under portal/src/app. | `.agents/skills/notch-portal-ui-conventions/SKILL.md` |
| notch-swift-cloud-api-conventions | Maintain cloud-facing Swift architecture and API contracts in the Notch macOS app. Use when adding, changing, debugging, or reviewing Sources/Notch/Portal, feature cloud sync/coordinators/repositories, URLSession clients, authenticated Portal context, durable outboxes, Codable API DTOs, or core events that feed cloud behavior. | `.agents/skills/notch-swift-cloud-api-conventions/SKILL.md` |
| notch-swift-ui-conventions | Build and review consistent SwiftUI and AppKit user experiences in Notch. Use when changing settings panes, panels, overlays, windows, reusable controls, visual styling, motion, accessibility, or view-to-feature state wiring under Sources/Notch. | `.agents/skills/notch-swift-ui-conventions/SKILL.md` |
| notch-verification-release | Verify, deploy, and release Notch changes with explicit evidence and rollback awareness. Use when completing substantial code changes, changing persisted contracts, deploying the Portal to Vercel, packaging/installing the macOS app, resetting data, or preparing a release. | `.agents/skills/notch-verification-release/SKILL.md` |
