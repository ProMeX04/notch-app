---
paths:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
  - "Package.swift"
---

# Swift Architecture Boundary

Read `docs/engineering/architecture-boundaries.md`. Core targets may not gain
new persistence, networking, authentication, keychain ownership, or
orchestration. Shared infrastructure must be neutrally owned and injected from
the app composition root.

For Portal transport, authentication, cloud sync, or durable outboxes, load
`notch-swift-cloud-api-conventions`.
