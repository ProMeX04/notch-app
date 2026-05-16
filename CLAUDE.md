# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- Build the Swift package: `swift build`
- Build the app bundle: `./build-app.sh`
- Build a clean app bundle after dependency/build issues: `CLEAN=1 ./build-app.sh`
- Build release app bundle: `RELEASE=1 ./build-app.sh`
- Build and open the app: `./dev-run.sh`
- Build and run with logs: `./script/build_and_run.sh --logs`
- Build and verify the app starts: `./script/build_and_run.sh --verify`
- Run all SwiftPM tests: `swift test`
- Run one executable-style test target: `swift run NotchFocusTests`, `swift run NotchSkillsTests`, `swift run NotchBridgeParserTests`, `swift run NotchMailParserTests`, `swift run NotchChatHistoryTests`, or `swift run NotchScreenShareTests`

There is no Xcode project required; this is a SwiftPM macOS app. `build-app.sh` performs an incremental `swift build`, patches SwiftPM's resource bundle accessor for the `.app` layout, builds again, copies resources/frameworks into `dist/Notch.app`, and ad-hoc signs it.

## Architecture overview

This repository is a macOS notch utility built with SwiftUI/AppKit. The main executable target is `Notch`; smaller core modules hold logic that is useful to test independently: focus, shelf, bridge parsing, mail parsing, chat history, Gemini skill storage, screen sharing, and Gemini tool support.

`Sources/Notch/App` is the composition/root layer. `NotchAppEnvironment` wires long-lived dependencies, `ApplicationBootstrapper` and `ApplicationCoordinator` manage startup and app lifecycle, and feature coordinators/controllers bridge app-level services into UI windows and menus. Prefer adding dependencies through this composition layer instead of reaching for new global singletons.

`Sources/Notch/NotchUI`, `SharedUI`, and `Window` contain the notch shell, shared SwiftUI views, and AppKit window/controller glue. The notch shell is intentionally split into focused files for header, compact activity, panel switcher, settings, and shell content.

`Sources/Notch/GeminiLive` is the largest subsystem. `GeminiLiveViewModel` remains the observable facade consumed by UI, while behavior is split into same-type extension files: backend/account setup, connection/reconnect lifecycle, media/mic/chat, prompts, skills, tool toasts, skill-writer approval, and UI state. Session-level protocol/tool implementation lives under `GeminiLive/Core` and `GeminiLive/Tools`; keep schema/dispatch concerns there and UI approval/state coordination in the view-model/coordinator layer.

`Sources/NotchTooling` contains Gemini workspace tool support that is still exposed to Gemini Live. The current local workspace tool surface is intentionally focused around read/payload/argument-normalization behavior; do not reintroduce removed write/edit/find/grep/ls tool code unless the product needs those tools again.

`Sources/Notch/Media`, `Focus`, `Jarvis`, `AgentResults`, `Shortcut`, and `Entitlements` are feature areas coordinated from the app layer. Many side-effectful services now have small protocols so tests and future refactors can avoid hard-coded shared instances.

## Tests

Several test suites are executable targets with manual `main.swift` runners, so `swift run <TargetName>` is often the most direct way to run a focused suite. The standard `swift test` command also exists for XCTest-based tests under `Tests/`.

## Portal

The web account/auth flow lives in `portal/`, which has its own `portal/CLAUDE.md`. When editing portal code, follow that file too; it points to important Next.js-version-specific guidance in `node_modules/next/dist/docs/`.
