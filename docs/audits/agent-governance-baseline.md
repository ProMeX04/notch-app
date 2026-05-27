# Agent Governance Debt Audit

Date: 2026-05-27

This audit records boundary debt detected while installing agent governance.
Because the repository is still in development, this is not an exception
baseline. `script/agent-governance.mjs check` must fail while these items remain.

## Findings

| Severity | Finding | Evidence | Remediation backlog |
| --- | --- | --- | --- |
| Resolved | `NotchShelfCore` owned Google Drive HTTP transport and credential/token storage while being named and governed as a pure core target. | Former `Sources/NotchShelfCore/NotchGoogleDriveService.swift` and `NotchShelfViewModel.swift`. | Reclassified to `Sources/NotchShelfFeature`; the target now advertises feature persistence/integration ownership instead of pretending to be pure core. |
| Resolved | Focus, Shelf, and chat-history packages used concrete `UserDefaults` while being named as core targets. | Former `Sources/NotchFocusCore`, `Sources/NotchShelfCore`, and `Sources/NotchChatHistoryCore`. | Reclassified to `NotchFocusFeature`, `NotchShelfFeature`, and `NotchChatHistoryFeature`. Pure `Sources/*Core` governance remains zero-baseline. |
| Resolved | Agent instructions duplicated Swift architecture guidance and could diverge across providers. | Root `CLAUDE.md` repeated root architecture rules; native skill copies had no generator/check. | `CLAUDE.md` now imports the shared charter; canonical skills/rules generate native mirrors and drift is validated. |
| Resolved | Architecture documentation attributed shared backend/account concerns to Gemini after Portal extraction. | Existing Gemini section referenced backend/account ownership without the shared Portal subsystem. | `docs/architecture.md` now records Portal ownership and Focus/Gemini consumers. |

## Zero-Baseline Rules

The following are forbidden immediately:

- Focus API route ownership selected from `body.user_id` or `body.device_id`.
- Public leaderboard projection using private `user.name`.
- Swift sync/outbox state stored in `UserDefaults`.

## Review Method

- Reviewed root and Portal instruction files, provider-native skills/rules, the
  updated Focus/Portal subsystem paths, and existing architecture documentation.
- Scanned all `Sources/*Core/**/*.swift` files for concrete networking,
  credential, and `UserDefaults` indicators.
- Scanned Focus Portal routes/services for client-owned ranking identity and
  private-name leaderboard fallback indicators.

## Next Remediation Order

1. Extract Google Drive transport and credential ownership from `NotchShelfFeature`.
2. Separate chat-history persistence and feature preference storage from core
   domain logic without changing user data semantics.
3. Expand governance detectors only when a deterministic false-positive-free
   rule is available, keeping review guidance for behavioral architecture checks.

## Completion Policy

Do not mark architecture/governance work complete while this audit lists High or
Medium unresolved findings. The correct remediation is code movement, target
reclassification, or boundary extraction, not increasing
`.agent-governance/baseline.json`.
