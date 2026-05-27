# Swift UI Patterns

This standard applies to SwiftUI/AppKit views, settings, panels, controls, and
window-facing state.

## Ownership And Composition

- Views render observable state and forward user intent. Networking, durable
  persistence, authentication, and retry scheduling remain in injected
  coordinators/stores.
- Add app-wide state through `NotchAppEnvironment` and feature coordinators; do
  not introduce view-owned service singletons.
- Use `SharedUI` primitives and existing settings row structure before adding a
  one-off visual implementation.

## Control And Layout Quality

- Use familiar native controls for their meaning: toggles for binary preferences,
  segmented controls for modes, sliders/steppers/fields for numeric values, and
  icon buttons with tooltips for compact commands.
- Keep compact surfaces information-dense and aligned with their neighboring
  controls. Do not turn an individual settings option into a promotional panel.
- Establish stable dimensions and responsive constraints for toolbars, counters,
  tiles, and dynamic labels so state changes do not shift adjacent UI.
- Text must remain legible and unoccluded at expected macOS window sizes and under
  localization or longer account/display values.

## Motion And Accessibility

- Animation must communicate state or hierarchy, not decorate idle screens.
- Respect reduced-motion preferences by disabling or simplifying nonessential
  transitions.
- Preserve keyboard navigation, VoiceOver labels, adequate contrast, and visible
  control state for every new user-facing control.

## Verification

Build after presentation changes and smoke-test the affected panel/window. For
startup wiring or major settings flows, run `./script/build_and_run.sh --verify`.
