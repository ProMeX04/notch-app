import AppKit
import Foundation

@MainActor
enum NotchCommandRouter {
    static func handle(url: URL, handler: NotchCommandHandling, entitlementStore: NotchEntitlementStore) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "notch" else {
            return
        }

        let host = components.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        let action = pathComponents.first ?? ""
        let queryItems = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }
        )

        do {
            switch host {
            case "panel":
                try handlePanel(action: action, queryItems: queryItems, handler: handler, entitlementStore: entitlementStore)
            case "visibility":
                try requireAccess(.deepLinkCommand(.visibility), entitlementStore: entitlementStore)
                try handleVisibility(action: action, handler: handler)
            case "pin":
                try requireAccess(.deepLinkCommand(.pin), entitlementStore: entitlementStore)
                try handlePin(action: action, handler: handler)
            case "talk":
                try handleTalk(action: action, handler: handler, entitlementStore: entitlementStore)
            case "screen":
                try requireAccess(.deepLinkCommand(.screen), entitlementStore: entitlementStore)
                try handleScreen(action: action, handler: handler)
            case "caption":
                try requireAccess(.deepLinkCommand(.caption), entitlementStore: entitlementStore)
                try handleCaption(action: action, handler: handler)
            case "focus":
                try requireAccess(.deepLinkCommand(.focus), entitlementStore: entitlementStore)
                try handleFocus(action: action, queryItems: queryItems, handler: handler)
            case "media":
                try requireAccess(.deepLinkCommand(.media), entitlementStore: entitlementStore)
                try handleMedia(action: action, queryItems: queryItems, handler: handler)
            case "oauth":
                try handleOAuth(url: url, action: action, handler: handler)
            default:
                throw NotchCommandError.unsupportedCommand(url.absoluteString)
            }
        } catch {
            NotchLog.app.error("Command routing failed for \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private static func handlePanel(
        action: String,
        queryItems: [String: String],
        handler: NotchCommandHandling,
        entitlementStore: NotchEntitlementStore
    ) throws {
        let panelName = firstNonEmpty(action, queryItems["name"], queryItems["panel"])
        guard let panel = panelName.flatMap(NotchPanel.init(rawValue:)) else {
            throw NotchCommandError.invalidValue("panel", action)
        }
        try requireAccess(.panelAccess(panel), entitlementStore: entitlementStore)
        try requireAccess(.deepLinkCommand(.panel), entitlementStore: entitlementStore)
        handler.showPanel(panel)
    }

    private static func handleVisibility(action: String, handler: NotchCommandHandling) throws {
        switch action {
        case "show":
            handler.show()
        case "hide":
            handler.hide()
        case "toggle":
            handler.toggleVisibility()
        default:
            throw NotchCommandError.invalidAction("visibility", action)
        }
    }

    private static func handlePin(action: String, handler: NotchCommandHandling) throws {
        switch action {
        case "on", "true", "pin":
            handler.setPinned(true)
        case "off", "false", "unpin":
            handler.setPinned(false)
        case "toggle":
            handler.togglePinned()
        default:
            throw NotchCommandError.invalidAction("pin", action)
        }
    }

    private static func handleTalk(
        action: String,
        handler: NotchCommandHandling,
        entitlementStore: NotchEntitlementStore
    ) throws {
        try requireAccess(.deepLinkCommand(.talk), entitlementStore: entitlementStore)
        switch action {
        case "show":
            handler.showTalkPanel()
        case "connect":
            try requireAccess(.talkConnection, entitlementStore: entitlementStore)
            handler.connectGeminiLive()
        case "disconnect":
            handler.disconnectGeminiLive()
        case "toggle":
            handler.toggleGeminiLive()
        case "mute", "mic-off":
            handler.muteGeminiLive()
        case "unmute", "mic-on":
            handler.unmuteGeminiLive()
        case "mic-toggle":
            handler.toggleGeminiLiveMicrophone()
        default:
            throw NotchCommandError.invalidAction("talk", action)
        }
    }

    private static func handleScreen(action: String, handler: NotchCommandHandling) throws {
        switch action {
        case "full", "fullscreen":
            handler.startFullScreenShare()
        case "region", "selection":
            handler.startRegionScreenShare()
        case "window", "app":
            handler.startWindowScreenShare()
        case "stop", "off", "clear":
            handler.stopScreenShare()
        default:
            throw NotchCommandError.invalidAction("screen", action)
        }
    }

    private static func handleCaption(action: String, handler: NotchCommandHandling) throws {
        switch action {
        case "on", "show", "enable":
            handler.setGeminiLiveCaptionsEnabled(true)
        case "off", "hide", "disable":
            handler.setGeminiLiveCaptionsEnabled(false)
        case "toggle":
            handler.toggleGeminiLiveCaptions()
        default:
            throw NotchCommandError.invalidAction("caption", action)
        }
    }

    private static func handleFocus(action: String, queryItems: [String: String], handler: NotchCommandHandling) throws {
        let toolName = firstNonEmpty(queryItems["tool"], queryItems["name"])
        try validatePomodoroTool(toolName)
        let duration = firstNonEmpty(queryItems["duration"], queryItems["value"])
        let breakDuration = firstNonEmpty(queryItems["break"], queryItems["breakduration"])
        let longBreakDuration = firstNonEmpty(queryItems["long"], queryItems["longbreak"], queryItems["long-break"])

        switch action {
        case "show":
            handler.showFocusPanel()
        case "set":
            try handler.configurePomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
        case "start":
            try handler.startPomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
        case "pause":
            try handler.pausePomodoro()
        case "resume":
            try handler.resumePomodoro()
        case "toggle":
            handler.togglePomodoro()
        case "reset":
            try handler.resetPomodoroSession()
        case "skip":
            handler.skipPomodoroPhase()
        case "phase":
            guard let phase = firstNonEmpty(queryItems["phase"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("phase")
            }
            try handler.setPomodoroPhase(phase)
        case "long-break", "longbreak":
            guard let duration = firstNonEmpty(queryItems["duration"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("duration")
            }
            try handler.setPomodoroLongBreak(duration: duration)
        case "cycle":
            guard let count = firstNonEmpty(queryItems["count"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("count")
            }
            try handler.setPomodoroCycle(count)
        case "auto-breaks", "autobreaks":
            guard let mode = try focusToggleMode(from: firstNonEmpty(queryItems["state"], queryItems["value"])) else {
                throw NotchCommandError.missingParameter("state")
            }
            handler.setPomodoroAutoBreaks(mode)
        case "auto-pomo", "autopomo", "auto-pomodoros":
            guard let mode = try focusToggleMode(from: firstNonEmpty(queryItems["state"], queryItems["value"])) else {
                throw NotchCommandError.missingParameter("state")
            }
            handler.setPomodoroAutoPomodoros(mode)
        default:
            throw NotchCommandError.invalidAction("focus", action)
        }
    }

    private static func handleMedia(action: String, queryItems: [String: String], handler: NotchCommandHandling) throws {
        switch action {
        case "play":
            handler.playMedia()
        case "pause":
            handler.pauseMedia()
        case "toggle", "playpause":
            handler.toggleMediaPlayback()
        case "stop":
            handler.stopMedia()
        case "next":
            handler.nextMediaTrack()
        case "previous", "prev":
            handler.previousMediaTrack()
        case "skip-forward", "forward":
            let seconds = try requiredSeconds(queryItems: queryItems)
            handler.skipMedia(seconds: seconds)
        case "skip-backward", "backward":
            let seconds = try requiredSeconds(queryItems: queryItems)
            handler.skipMedia(seconds: -seconds)
        case "open":
            handler.openCurrentMediaApp()
        case "volume":
            guard let levelRaw = queryItems["level"], let level = Double(levelRaw) else {
                throw NotchCommandError.missingParameter("level")
            }
            handler.setMediaVolume(level)
        default:
            throw NotchCommandError.invalidAction("media", action)
        }
    }

    private static func handleOAuth(url: URL, action: String, handler: NotchCommandHandling) throws {
        switch action {
        case "callback":
            handler.handleOAuthCallback(url)
        default:
            throw NotchCommandError.invalidAction("oauth", action)
        }
    }

    private static func requiredSeconds(queryItems: [String: String]) throws -> Double {
        guard let raw = firstNonEmpty(queryItems["seconds"], queryItems["secs"], queryItems["value"]),
              let seconds = Double(raw) else {
            throw NotchCommandError.missingParameter("seconds")
        }
        return seconds
    }

    private static func requireAccess(_ capability: NotchCapability, entitlementStore: NotchEntitlementStore) throws {
        let decision = entitlementStore.decision(for: capability)
        guard decision.isAllowed else {
            throw NotchCommandError.permissionDenied(decision.message)
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.lowercased()
            }
        }
        return nil
    }

    private static func validatePomodoroTool(_ raw: String?) throws {
        guard let raw else { return }
        guard raw == "pomodoro" else {
            throw NotchCommandError.invalidValue("tool", raw)
        }
    }

    private static func focusToggleMode(from raw: String?) throws -> FocusToggleMode? {
        guard let raw else { return nil }
        switch raw {
        case "on", "true", "enable", "enabled":
            return .on
        case "off", "false", "disable", "disabled":
            return .off
        case "toggle":
            return .toggle
        default:
            throw NotchCommandError.invalidValue("state", raw)
        }
    }
}

private enum NotchCommandError: LocalizedError {
    case unsupportedCommand(String)
    case invalidAction(String, String)
    case invalidValue(String, String)
    case missingParameter(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(command):
            return "Unsupported command: \(command)"
        case let .invalidAction(domain, action):
            return "Invalid action '\(action)' for \(domain)."
        case let .invalidValue(name, value):
            return "Invalid \(name) value '\(value)'."
        case let .missingParameter(name):
            return "Missing required parameter '\(name)'."
        case let .permissionDenied(message):
            return message
        }
    }
}
