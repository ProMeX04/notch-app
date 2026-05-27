---
name: notch-portal-ui-conventions
description: Build and review polished, consistent Portal interfaces in Notch. Use when changing Next.js pages, React components, CSS, layouts, public leaderboard or account experiences, admin screens, responsive behavior, motion, loading/error states, or accessibility under portal/src/app.
---

# Notch Portal UI Conventions

Use this workflow for Portal presentation changes.

## Read First

1. Read `portal/AGENTS.md` and `docs/engineering/portal-ui-patterns.md`.
2. Read relevant Next.js documentation under `portal/node_modules/next/dist/docs/`.
3. Inspect the closest comparable page/component/style and its service/API
   contract before changing UI.

## Required Pattern

- Keep auth, ranking, privacy, and other business calculations in services/APIs;
  pages render approved contracts and local interaction state.
- Reuse established typography, spacing, icon, button, form, and feedback
  patterns. Keep admin layouts dense and operational.
- Use `/leaderboard` as the presentation baseline for public ranking work.
- Cover loading, empty, failure, disabled, keyboard, focus, and narrow/desktop
  layouts.

## Motion And Verification

- Use motion only for meaningful transition or feedback and support
  `prefers-reduced-motion`.
- Avoid geometry shifts, overlapping text, invisible actions, and decorative
  clutter that reduces scanability.

Run from `portal/`:

```bash
npm run lint
npm run build
```

Run related feature tests and visually inspect desktop/mobile rendering for user
facing changes.
