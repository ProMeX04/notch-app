import AppKit
import Foundation

@MainActor
enum NotchCommandRouter {
    static func handle(url: URL, controller: NotchWindowController) {
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
                try handlePanel(action: action, queryItems: queryItems, controller: controller)
            case "visibility":
                try handleVisibility(action: action, controller: controller)
            case "pin":
                try handlePin(action: action, controller: controller)
            case "talk":
                try handleTalk(action: action, controller: controller)
            case "screen":
                try handleScreen(action: action, controller: controller)
            case "caption":
                try handleCaption(action: action, controller: controller)
            case "focus":
                try handleFocus(action: action, queryItems: queryItems, controller: controller)
            case "media":
                try handleMedia(action: action, queryItems: queryItems, controller: controller)
            default:
                throw NotchCommandError.unsupportedCommand(url.absoluteString)
            }
        } catch {
            NotchLog.app.error("Command routing failed for \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private static func handlePanel(action: String, queryItems: [String: String], controller: NotchWindowController) throws {
        let panelName = firstNonEmpty(action, queryItems["name"], queryItems["panel"])
        guard let panel = panelName.flatMap(NotchPanel.init(rawValue:)) else {
            throw NotchCommandError.invalidValue("panel", action)
        }
        controller.showPanel(panel)
    }

    private static func handleVisibility(action: String, controller: NotchWindowController) throws {
        switch action {
        case "show":
            controller.show()
        case "hide":
            controller.hide()
        case "toggle":
            controller.toggleVisibility()
        default:
            throw NotchCommandError.invalidAction("visibility", action)
        }
    }

    private static func handlePin(action: String, controller: NotchWindowController) throws {
        switch action {
        case "on", "true", "pin":
            controller.setPinned(true)
        case "off", "false", "unpin":
            controller.setPinned(false)
        case "toggle":
            controller.togglePinned()
        default:
            throw NotchCommandError.invalidAction("pin", action)
        }
    }

    private static func handleTalk(action: String, controller: NotchWindowController) throws {
        switch action {
        case "show":
            controller.showTalkPanel()
        case "connect":
            controller.connectGeminiLive()
        case "disconnect":
            controller.disconnectGeminiLive()
        case "toggle":
            controller.toggleGeminiLive()
        case "mute", "mic-off":
            controller.muteGeminiLive()
        case "unmute", "mic-on":
            controller.unmuteGeminiLive()
        case "mic-toggle":
            controller.toggleGeminiLiveMicrophone()
        default:
            throw NotchCommandError.invalidAction("talk", action)
        }
    }

    private static func handleScreen(action: String, controller: NotchWindowController) throws {
        switch action {
        case "full", "fullscreen":
            controller.startFullScreenShare()
        case "region", "selection":
            controller.startRegionScreenShare()
        case "window", "app":
            controller.startWindowScreenShare()
        case "stop", "off", "clear":
            controller.stopScreenShare()
        default:
            throw NotchCommandError.invalidAction("screen", action)
        }
    }

    private static func handleCaption(action: String, controller: NotchWindowController) throws {
        switch action {
        case "on", "show", "enable":
            controller.setGeminiLiveCaptionsEnabled(true)
        case "off", "hide", "disable":
            controller.setGeminiLiveCaptionsEnabled(false)
        case "toggle":
            controller.toggleGeminiLiveCaptions()
        default:
            throw NotchCommandError.invalidAction("caption", action)
        }
    }

    private static func handleFocus(action: String, queryItems: [String: String], controller: NotchWindowController) throws {
        let toolName = firstNonEmpty(queryItems["tool"], queryItems["name"])
        try validatePomodoroTool(toolName)
        let duration = firstNonEmpty(queryItems["duration"], queryItems["value"])
        let breakDuration = firstNonEmpty(queryItems["break"], queryItems["breakduration"])
        let longBreakDuration = firstNonEmpty(queryItems["long"], queryItems["longbreak"], queryItems["long-break"])

        switch action {
        case "show":
            controller.showPomodoroPanel()
        case "set":
            try controller.configurePomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
        case "start":
            try controller.startPomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
        case "pause":
            try controller.pausePomodoro()
        case "resume":
            try controller.resumePomodoro()
        case "toggle":
            controller.togglePomodoroSession()
        case "reset":
            try controller.resetPomodoroSession()
        case "skip":
            controller.skipPomodoroPhase()
        case "phase":
            guard let phase = firstNonEmpty(queryItems["phase"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("phase")
            }
            try controller.setPomodoroPhase(phase)
        case "preset":
            guard let preset = firstNonEmpty(queryItems["preset"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("preset")
            }
            try controller.selectPomodoroPreset(preset)
        case "long-break", "longbreak":
            guard let duration = firstNonEmpty(queryItems["duration"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("duration")
            }
            try controller.setPomodoroLongBreak(duration: duration)
        case "cycle":
            guard let count = firstNonEmpty(queryItems["count"], queryItems["value"]) else {
                throw NotchCommandError.missingParameter("count")
            }
            try controller.setPomodoroCycle(count)
        case "auto-breaks", "autobreaks":
            guard let mode = try focusToggleMode(from: firstNonEmpty(queryItems["state"], queryItems["value"])) else {
                throw NotchCommandError.missingParameter("state")
            }
            controller.setPomodoroAutoBreaks(mode)
        case "auto-pomo", "autopomo", "auto-pomodoros":
            guard let mode = try focusToggleMode(from: firstNonEmpty(queryItems["state"], queryItems["value"])) else {
                throw NotchCommandError.missingParameter("state")
            }
            controller.setPomodoroAutoPomodoros(mode)
        default:
            throw NotchCommandError.invalidAction("focus", action)
        }
    }

    private static func handleMedia(action: String, queryItems: [String: String], controller: NotchWindowController) throws {
        switch action {
        case "play":
            controller.playMedia()
        case "pause":
            controller.pauseMedia()
        case "toggle", "playpause":
            controller.toggleMediaPlayback()
        case "stop":
            controller.stopMedia()
        case "next":
            controller.nextMediaTrack()
        case "previous", "prev":
            controller.previousMediaTrack()
        case "skip-forward", "forward":
            let seconds = try requiredSeconds(queryItems: queryItems)
            controller.skipMedia(seconds: seconds)
        case "skip-backward", "backward":
            let seconds = try requiredSeconds(queryItems: queryItems)
            controller.skipMedia(seconds: -seconds)
        case "open":
            controller.openCurrentMediaApp()
        case "volume":
            guard let levelRaw = queryItems["level"], let level = Double(levelRaw) else {
                throw NotchCommandError.missingParameter("level")
            }
            controller.setMediaVolume(level)
        default:
            throw NotchCommandError.invalidAction("media", action)
        }
    }

    private static func requiredSeconds(queryItems: [String: String]) throws -> Double {
        guard let raw = firstNonEmpty(queryItems["seconds"], queryItems["secs"], queryItems["value"]),
              let seconds = Double(raw) else {
            throw NotchCommandError.missingParameter("seconds")
        }
        return seconds
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

    private static func firstNonEmptyRaw(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
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
        }
    }
}
