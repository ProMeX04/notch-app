# Swift Source Guidance

Read `../docs/engineering/architecture-boundaries.md` for all source changes.

- For `Notch/Portal/**`, cloud sync, authenticated clients, or outboxes, use the
  native `notch-swift-cloud-api-conventions` skill.
- For SwiftUI/AppKit views, settings, panels, windows, or visual primitives, use
  the native `notch-swift-ui-conventions` skill.
- Core targets must remain free of newly introduced networking, authentication,
  keychain ownership, and durable sync persistence.
