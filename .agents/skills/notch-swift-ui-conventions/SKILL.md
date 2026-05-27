---
name: notch-swift-ui-conventions
description: Build and review consistent SwiftUI and AppKit user experiences in Notch. Use when changing settings panes, panels, overlays, windows, reusable controls, visual styling, motion, accessibility, or view-to-feature state wiring under Sources/Notch.
---

# Notch Swift UI Conventions

Use this workflow for user-facing macOS presentation work.

## Read First

1. Read `docs/engineering/swift-ui-patterns.md` and
   `docs/engineering/architecture-boundaries.md`.
2. Inspect the closest equivalent view and shared component under
   `Sources/Notch/SharedUI`, `Sources/Notch/App`, `Sources/Notch/NotchUI`, or
   `Sources/Notch/Window`.
3. Identify the injected state owner and the interaction states: loading,
   disabled, empty, error, authenticated/offline, and accessibility behavior.

## Required Pattern

- Keep business work in feature/coordinator state; views render and forward
  intent.
- Reuse the existing settings row/control and typography/spacing language before
  creating any custom visual surface.
- Use native-purpose controls and stable layout constraints; no ad hoc promoted
  cards for individual preferences.
- Keep shared visual primitives generic and feature-specific views inside their
  owning feature or app settings layer.

## Quality Gate

- Verify long labels and dynamic state do not clip or shift adjacent content.
- Supply labels/tooltips/focus behavior for icon-only or unfamiliar controls.
- Respect reduced motion and verify animation cannot obscure interaction or text.
- Build and manually inspect the affected view; use app verification when wiring
  or window lifecycle changes.

Run:

```bash
swift build
```

Run relevant focused tests and `./script/build_and_run.sh --verify` for
integration-sensitive changes.
