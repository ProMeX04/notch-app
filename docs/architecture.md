# Notch Architecture

This document maps the current architecture and the boundaries to preserve as the app grows.

## Package layout

Notch is a SwiftPM-first macOS app. [Package.swift](../Package.swift) is the source of truth for products, targets, resources, and test executables.

| Area | Path | Responsibility |
| --- | --- | --- |
| App executable | [Sources/Notch](../Sources/Notch/) | macOS app shell, SwiftUI/AppKit integration, runtime service wiring, feature presentation, platform adapters. |
| Tooling core | [Sources/NotchTooling](../Sources/NotchTooling/) | Reusable Gemini/tool argument normalization and response payload helpers. |
| Focus feature package | [Sources/NotchFocusFeature](../Sources/NotchFocusFeature/) | Pomodoro feature state, preferences, and domain events that can run without the app shell. |
| Shelf feature package | [Sources/NotchShelfFeature](../Sources/NotchShelfFeature/) | Shelf state, feature persistence, Google Drive integration, and item handling. |
| Chat history feature package | [Sources/NotchChatHistoryFeature](../Sources/NotchChatHistoryFeature/) | Gemini chat suggestion history and its feature persistence. |
| Browser bridge parser core | [Sources/NotchBridgeParserCore](../Sources/NotchBridgeParserCore/) | Browser bridge protocol parsing. |
| Mail parser core | [Sources/NotchMailParserCore](../Sources/NotchMailParserCore/) | Apple Mail body parsing independent of Gemini Live or UI concerns. |
| Tests | [Tests](../Tests/) and executable targets under [Sources](../Sources/) | Lightweight executable regression suites and XCTest coverage. |

Code belongs in a core target when it is independent of AppKit/SwiftUI lifecycle, app windows, user defaults specific to the app shell, and concrete platform services. Code belongs in [Sources/Notch](../Sources/Notch/) when it adapts core logic to macOS services, windows, menus, permissions, browser bridges, audio devices, or Gemini Live sessions.

## App target folder conventions

- [App](../Sources/Notch/App/) owns lifecycle, bootstrap, composition, routing, and settings shell code.
- [AppServices](../Sources/Notch/AppServices/) owns macOS/platform/runtime services such as notifications, status item, launch-at-login, permissions, sound, hotkeys, resources, learning stats, and system audio.
- [Entitlements](../Sources/Notch/Entitlements/) owns capability manifests, entitlement state, Pro gating, and web portal policy helpers.
- [SharedUI](../Sources/Notch/SharedUI/) owns reusable app UI primitives and wrappers.
- [Utilities](../Sources/Notch/Utilities/) owns generic helpers, extensions, scripting wrappers, and logging.
- [NotchUI](../Sources/Notch/NotchUI/) owns the shared notch composition surface and cross-feature panels.
- [Media](../Sources/Notch/Media/) owns media playback state, media controllers, visualizers, and media-specific views.
- [Portal](../Sources/Notch/Portal/) owns shared backend configuration, device identity, authenticated account/session state, and Portal transport used by app features.
- [Focus](../Sources/Notch/Focus/) owns focus runtime adapters plus its Portal synchronization repository/coordinator; ranking persistence does not belong in focus core.

## Startup and composition

Startup flows through a small set of app-layer objects:

1. [NotchApp.swift](../Sources/Notch/App/NotchApp.swift) is the SwiftUI entry point.
2. [NotchAppDelegate.swift](../Sources/Notch/App/NotchAppDelegate.swift) bridges into AppKit lifecycle events.
3. [ApplicationBootstrapper.swift](../Sources/Notch/App/ApplicationBootstrapper.swift) configures process-level app behavior, status item, notifications, settings, hotkeys, screen observation, and service startup.
4. [ApplicationCoordinator.swift](../Sources/Notch/App/ApplicationCoordinator.swift) owns app runtime start/stop coordination.
5. [NotchAppEnvironment.swift](../Sources/Notch/App/NotchAppEnvironment.swift) is the composition root. It constructs feature view models, controllers, and cross-feature adapters.

The composition root should assemble dependencies and install integration adapters. Feature behavior should stay in feature-specific coordinators, view models, or core targets rather than accumulating inside the environment. App-specific Gemini Live integration belongs in [GeminiLiveFeatureBridge.swift](../Sources/Notch/App/GeminiLiveFeatureBridge.swift), not in the reusable session/tool files.

`NotchAppEnvironment` owns one Portal account coordinator. Account settings,
Focus cloud sync, Shelf Portal links, and managed Gemini server flows consume that
shared context rather than maintaining feature-owned copies of login state.

## Major runtime boundaries

### App shell and presentation

- [NotchWindowController.swift](../Sources/Notch/Window/NotchWindowController.swift) hosts the main notch UI and overlay windows.
- [NotchPresentationModel.swift](../Sources/Notch/Window/NotchPresentationModel.swift) owns presentation state such as expanded/collapsed mode and selected panel.
- [StatusItemController.swift](../Sources/Notch/AppServices/StatusItemController.swift) adapts app commands to the menu bar.

The shell should present state and forward user intent; feature-specific decisions should remain in feature coordinators or view models.

### Command routing

- [NotchFeatureCoordinator.swift](../Sources/Notch/App/NotchFeatureCoordinator.swift) is the app command facade for media, focus, shelf, Gemini Live, settings, and panel actions.
- [NotchCommandRouting.swift](../Sources/Notch/App/NotchCommandRouting.swift) parses and routes `notchctl`/URL-style commands.

This layer is intentionally broad, but new command families should be grouped behind focused methods or adapters to avoid turning the coordinator into a second composition root.

### Focus and browser bridge

- [NotchFocusFeature](../Sources/NotchFocusFeature/) owns reusable Pomodoro feature state and behavior.
- [FocusBrowserBridgeServer.swift](../Sources/Notch/Focus/FocusBrowserBridgeServer.swift) adapts focus features to the browser extension bridge.
- [PomodoroSupportAdapters.swift](../Sources/Notch/Focus/PomodoroSupportAdapters.swift) connects focus core abstractions to app services such as notifications and sounds.
- [FocusDailyStatsRepository.swift](../Sources/Notch/Focus/FocusDailyStatsRepository.swift) owns atomic daily aggregate/outbox persistence for cloud ranking.
- [FocusCloudSyncCoordinator.swift](../Sources/Notch/Focus/FocusCloudSyncCoordinator.swift) owns authenticated sync/profile orchestration using shared Portal account context.

The browser bridge, daily repository, and cloud coordinator are app/runtime
infrastructure, so they stay outside focus core. Focus core emits domain meaning
such as focused intervals and completed sessions; it does not infer or persist
ranking aggregates.

### Shelf

- [NotchShelfFeature](../Sources/NotchShelfFeature/) owns shelf feature state, persistence, Google Drive integration, and item behavior.
- App code should import the feature package normally, not through `@testable`, so the package boundary reflects real production API needs.

### Media and system audio

- [MediaProbeViewModel.swift](../Sources/Notch/Media/MediaProbeViewModel.swift) exposes media state to UI.
- [NowPlayingController.swift](../Sources/Notch/Media/NowPlayingController.swift) adapts MediaRemote/private framework access.
- [SystemAudioOutput.swift](../Sources/Notch/AppServices/SystemAudioOutput.swift) isolates system output volume and mute behavior.

System audio and media-remote integrations are platform adapters and should not leak into reusable core targets.

## Gemini Live architecture

Gemini Live is currently the most complex subsystem.

Gemini Live files are grouped by responsibility under [Sources/Notch/GeminiLive](../Sources/Notch/GeminiLive/):

- [Core](../Sources/Notch/GeminiLive/Core/) owns Gemini session lifecycle, shared models, Gemini Portal endpoint clients, skill support, logging, and canonical tool names.
- [Tools](../Sources/Notch/GeminiLive/Tools/) owns tool schema, function-call dispatch, response helpers, and tool implementations grouped by domain.
- [UI](../Sources/Notch/GeminiLive/UI/) owns UI-facing Talk state, controllers, approval UI, hold-to-talk, and transcript overlays.
- [Audio](../Sources/Notch/GeminiLive/Audio/) owns audio capture/playback extensions and WebRTC audio IO.
- [Services](../Sources/Notch/GeminiLive/Services/) owns local service helpers such as Mail, Spotlight, transcript storage, and chat history.
- [ScreenShare](../Sources/Notch/GeminiLive/ScreenShare/) owns screen/window selection and screen-share highlighting.
- [GeminiLiveFeatureBridge.swift](../Sources/Notch/App/GeminiLiveFeatureBridge.swift) stays in the app layer because it wires Gemini Live callbacks to app-owned feature objects.

Important files:
- [GeminiLiveSession.swift](../Sources/Notch/GeminiLive/Core/GeminiLiveSession.swift) owns live transport, session state, reconnect mechanics, tool callbacks, and outbound/inbound protocol messages.
- [GeminiLiveSession+ToolSchema.swift](../Sources/Notch/GeminiLive/Tools/GeminiLiveSession+ToolSchema.swift) builds the Gemini Live setup tool declarations.
- [GeminiLiveSession+ToolDispatch.swift](../Sources/Notch/GeminiLive/Tools/GeminiLiveSession+ToolDispatch.swift) routes Gemini function calls by tool name.

Current flow:

```text
GeminiLiveViewModel
  -> GeminiLiveSession
    -> WebSocket/audio protocol handling
    -> function call parsing
    -> tool dispatch
      -> app bridges, local services, NotchTooling helpers
```

Target direction:

```text
GeminiLiveViewModel
  -> session/coordinator interfaces
    -> GeminiLiveSession for transport/audio/session lifecycle
    -> Gemini tool registry for schema + routing
    -> app feature bridge for Focus/Media/Memory/Browser commands
    -> local data services for Mail/Spotlight/filesystem access
```

Near-term changes should keep the current public `GeminiLiveSession` and `GeminiLiveViewModel` surfaces stable. Prefer extracting small seams, centralizing names/constants, and moving wiring into adapters over rewriting the tool system in one pass.

## Local data tools

- [MailSQLiteManager.swift](../Sources/Notch/GeminiLive/Services/MailSQLiteManager.swift) provides read-only access to Apple Mail indexes and `.emlx` resolution.
- [SpotlightManager.swift](../Sources/Notch/GeminiLive/Services/SpotlightManager.swift) wraps `NSMetadataQuery` for local file search.
- [AppleMailBodyParser.swift](../Sources/NotchMailParserCore/AppleMailBodyParser.swift) is already correctly isolated as parser-only logic.

Mail and Spotlight access are local data services, not Gemini-specific concepts. They currently live under Gemini Live because Gemini tools are their only caller. If another feature needs them, move them to neutral app service ownership or a dedicated core target if they become testable and UI-independent.

## Testing

Common verification commands:

```sh
swift build
swift test
swift run NotchFocusTests
swift run NotchBridgeParserTests
swift run NotchMailParserTests
swift run NotchShelfTests
swift run NotchToolParityTests
```

Use targeted executable suites when changing a specific core. Use `swift build` after app-layer refactors because many runtime integrations are not covered by unit tests.

For UI-impacting changes, also launch the app and smoke-test the affected panels. Build and test suites verify compilation and core behavior; they do not prove menu bar, window, permission, audio, or overlay behavior.

## Architecture rules

- Keep reusable business/domain logic in core targets when it does not require AppKit, SwiftUI app lifecycle, concrete permissions, feature persistence, or local machine services.
- Keep macOS adapters in [Sources/Notch](../Sources/Notch/).
- Do not use `@testable import` from production app code.
- Keep [NotchAppEnvironment.swift](../Sources/Notch/App/NotchAppEnvironment.swift) focused on dependency construction and adapter installation.
- Co-locate schema, routing, and implementation for new Gemini tools when practical, or at least centralize tool names to avoid drift.
- Prefer small typed adapters over long lists of unrelated closures when wiring cross-feature dependencies.
- Move services out of feature folders when their ownership becomes broader than the feature that first introduced them.
- Keep Portal account/auth ownership in `Sources/Notch/Portal`; Gemini and Focus are consumers, not authentication authorities.
- Keep cloud sync repositories and pending state out of reusable core targets and `UserDefaults`.
