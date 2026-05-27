# Architecture Boundaries

This standard is the canonical source for module ownership decisions in Notch.
Agent-specific rules must point here rather than restating these boundaries.

## Swift App

- `Sources/*Core` is for deterministic domain logic, value models, domain events,
  and protocols. New networking, authentication, keychain access, app lifecycle
  orchestration, and durable sync persistence do not belong there.
- Feature packages that intentionally own user preferences, local persistence, or
  service integrations must use a `*Feature` target name, not `*Core`.
- `Sources/Notch/App/NotchAppEnvironment.swift` is the composition root. Construct
  shared long-lived dependencies once and inject narrow interfaces into features.
- `Sources/Notch/Portal` owns shared Portal backend configuration, authenticated
  session/account state, device context, refresh behavior, and shared transport.
- A feature owns its feature-specific behavior and persistence. Focus owns ranking
  sync/coordinator/repository; Gemini owns Gemini endpoints and Talk lifecycle.
- Durable aggregate and pending-sync state must be stored through an atomic file
  repository under Application Support. Preferences may use `UserDefaults`;
  recoverable cloud state and outboxes may not.

## Portal

- A route handler parses input, resolves authentication/authorization, invokes a
  feature service, records route-level event outcomes where required, and forms
  the response.
- Validation, idempotency, aggregation, ranking/query policy, privacy projection,
  and database mutations belong in `src/lib` or feature services.
- Pages/components consume API or service results. They must not duplicate
  identity, authorization, pricing, ranking, or privacy rules.

## Dependency Decisions

- Prefer an existing owner and protocol before introducing a new shared service.
- When a service becomes useful to more than one feature, move it to a neutral
  subsystem instead of letting the first consumer become its permanent owner.
- Add a new abstraction only when it enforces a boundary, enables deterministic
  testing, or removes meaningful duplication.

## Development Debt Policy

This repository is in development mode. Existing architecture debt is not
grandfathered and must not be hidden behind allowlists. If governance detects a
boundary violation, move the code to the correct owner or introduce the proper
injected boundary before completing the task.

Development-mode data changes are clean breaks. Do not preserve obsolete local
or cloud data by adding legacy decoders, migration branches, or fallback readers.
Reset dev data and keep the current model as the single source of truth unless
the user explicitly requests production data retention.
