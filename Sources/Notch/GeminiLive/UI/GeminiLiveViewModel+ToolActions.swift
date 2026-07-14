import Foundation
import SwiftUI

extension GeminiLiveViewModel {
    func startedToolAction(for name: String) -> ToolActionToast? {
        switch name {
        case "webSearch":
            return ToolActionToast(label: Localization.get("Searching web…"), icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: Localization.get("Reading file…"), icon: "doc.text", showsInOverlay: false)
        case "calendar":
            return ToolActionToast(label: Localization.get("Checking calendar…"), icon: "calendar", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: Localization.get("Listing files…"), icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: Localization.get("Using clipboard…"), icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: Localization.get("Controlling app…"), icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: Localization.get("Controlling media…"), icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: Localization.get("Controlling timer…"), icon: "timer", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: Localization.get("Running command…"), icon: "terminal", showsInOverlay: false)
        default:
            return nil
        }
    }

    nonisolated func completedToolAction(
        for name: String,
        args: [String: Any],
        result: [String: Any],
        success: Bool,
        error: String?,
        message: String?
    ) -> ToolActionToast? {
        if !success {
            let label = error ?? message ?? failedToolActionLabel(for: name)
            return ToolActionToast(label: label, icon: "exclamationmark.triangle", showsInOverlay: false)
        }

        switch name {
        case "webSearch":
            return ToolActionToast(label: webSearchToolActionLabel(args: args, result: result), icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: readToolActionLabel(args: args, result: result), icon: "doc.text", showsInOverlay: false)
        case "calendar":
            return ToolActionToast(label: calendarToolActionLabel(args: args, result: result, message: message), icon: "calendar", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: listToolActionLabel(args: args, result: result), icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: clipboardToolActionLabel(args: args, result: result, message: message), icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: appControlToolActionLabel(args: args, result: result, message: message), icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: mediaControlToolActionLabel(args: args, result: result), icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: pomodoroToolActionLabel(args: args, result: result, message: message), icon: "timer", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: execToolActionLabel(args: args, result: result, message: message), icon: "terminal", showsInOverlay: false)
        default:
            return nil
        }
    }

    private nonisolated func webSearchToolActionLabel(args: [String: Any], result: [String: Any]) -> String {
        if let query = stringValue(args, "query") ?? stringValue(args, "q") {
            return "Searched: \(query)"
        }
        if let count = intValue(result, "count") ?? intValue(result, "resultCount") {
            return count == 1 ? "Found 1 web result" : "Found \(count) web results"
        }
        return "Web search completed"
    }

    private nonisolated func readToolActionLabel(args: [String: Any], result: [String: Any]) -> String {
        if let path = stringValue(args, "path") {
            return "Read \(shortName(path))"
        }
        if let bytes = intValue(result, "bytes") {
            return "Read \(bytes) bytes"
        }
        return "Read file"
    }

    private nonisolated func listToolActionLabel(args: [String: Any], result: [String: Any]) -> String {
        let count = intValue(result, "count") ?? intValue(result, "itemCount")
        if let path = stringValue(args, "path") {
            if let count {
                return count == 1 ? "Listed 1 item in \(shortName(path))" : "Listed \(count) items in \(shortName(path))"
            }
            return "Listed \(shortName(path))"
        }
        if let count {
            return count == 1 ? "Listed 1 item" : "Listed \(count) items"
        }
        return "Listed files"
    }

    private nonisolated func clipboardToolActionLabel(args: [String: Any], result: [String: Any], message: String?) -> String {
        switch stringValue(args, "action") {
        case "read":
            let length = stringValue(result, "stdout")?.count ?? 0
            return length > 0 ? "Read clipboard (\(length) chars)" : "Clipboard is empty"
        case "write":
            return message ?? "Copied text"
        case "copy-file":
            return message ?? "Copied files"
        default:
            return message ?? "Clipboard action completed"
        }
    }

    private nonisolated func appControlToolActionLabel(args: [String: Any], result: [String: Any], message: String?) -> String {
        let appName = stringValue(result, "appName") ?? stringValue(args, "appName") ?? "App"
        switch stringValue(args, "action") {
        case "open":
            return message ?? "Opened \(appName)"
        case "quit":
            return message ?? "Quit \(appName)"
        case "check":
            if let isRunning = result["isRunning"] as? Bool {
                return isRunning ? "\(appName) is running" : "\(appName) is not running"
            }
            return "Checked \(appName)"
        default:
            return message ?? "App action completed"
        }
    }

    private nonisolated func mediaControlToolActionLabel(args: [String: Any], result: [String: Any]) -> String {
        switch stringValue(args, "action") {
        case "status":
            if let title = stringValue(result, "title") ?? stringValue(result, "track") {
                return "Now playing: \(title)"
            }
            return "Checked media status"
        case "volume-get":
            if let volume = intValue(result, "volume") {
                return "Volume is \(volume)%"
            }
            return "Checked volume"
        case "volume-set":
            if let volume = intValue(result, "volume") ?? intValue(args, "volumeLevel") {
                return "Set volume to \(volume)%"
            }
            return "Set volume"
        case "play":
            return "Started playback"
        case "pause":
            return "Paused playback"
        case "toggle":
            return "Toggled playback"
        case "next":
            return "Skipped to next track"
        case "previous":
            return "Returned to previous track"
        case "skip-forward":
            return "Skipped forward \(stringValue(args, "skipSeconds") ?? "15")s"
        case "skip-backward":
            return "Skipped back \(stringValue(args, "skipSeconds") ?? "15")s"
        default:
            return "Media action completed"
        }
    }

    private nonisolated func pomodoroToolActionLabel(args: [String: Any], result: [String: Any], message: String?) -> String {
        switch stringValue(args, "action") {
        case "status":
            return "Checked focus timer"
        case "start":
            return "Started focus timer"
        case "pause":
            return "Paused focus timer"
        case "resume":
            return "Resumed focus timer"
        case "reset":
            return "Reset focus timer"
        case "skip":
            return "Skipped focus phase"
        case "set":
            return "Updated focus timer"
        default:
            return message ?? "Focus action completed"
        }
    }

    private nonisolated func execToolActionLabel(args: [String: Any], result: [String: Any], message: String?) -> String {
        let command = stringValue(args, "command").map(shortCommand)
        if let exitCode = intValue(result, "exitCode") {
            if let command {
                return exitCode == 0 ? "Ran: \(command)" : "Command failed (\(exitCode)): \(command)"
            }
            return exitCode == 0 ? "Command finished" : "Command failed (\(exitCode))"
        }
        return message ?? command.map { "Ran: \($0)" } ?? "Command executed"
    }



    private nonisolated func calendarToolActionLabel(args: [String: Any], result: [String: Any], message: String?) -> String {
        let action = (result["action"] as? String) ?? (args["action"] as? String)
        switch action {
        case "create":
            if let title = nestedString(result, key: "event", nestedKey: "title") {
                return "Added event: \(title)"
            }
            return message ?? "Added event"
        case "delete":
            return message ?? "Deleted event"
        case "list":
            let count = (result["eventCount"] as? Int) ?? (result["count"] as? Int)
            if let count {
                return count == 1 ? "Found 1 event" : "Found \(count) events"
            }
            return "Listed events"
        case "calendars":
            if let count = result["calendarCount"] as? Int {
                return count == 1 ? "Found 1 calendar" : "Found \(count) calendars"
            }
            return "Listed calendars"
        case "list_reminders":
            if let count = result["reminderCount"] as? Int {
                return count == 1 ? "Found 1 reminder" : "Found \(count) reminders"
            }
            return "Listed reminders"
        case "create_reminder":
            if let title = nestedString(result, key: "reminder", nestedKey: "title") {
                return "Added reminder: \(title)"
            }
            return message ?? "Added reminder"
        case "complete_reminder":
            return message ?? "Completed reminder"
        case "delete_reminder":
            return message ?? "Deleted reminder"
        default:
            return message ?? "Calendar action completed"
        }
    }

    private nonisolated func nestedString(_ dictionary: [String: Any], key: String, nestedKey: String) -> String? {
        guard let nested = dictionary[key] as? [String: Any],
              let value = nested[nestedKey] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value
    }

    private nonisolated func stringValue(_ dictionary: [String: Any], _ key: String) -> String? {
        if let value = dictionary[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = dictionary[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private nonisolated func intValue(_ dictionary: [String: Any], _ key: String) -> Int? {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        if let value = dictionary[key] as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated func shortName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(separator: "/").last else { return trimmed }
        return String(last)
    }

    private nonisolated func shortCommand(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 42 else { return trimmed }
        return String(trimmed.prefix(39)) + "…"
    }

    private nonisolated func failedToolActionLabel(for name: String) -> String {
        switch name {
        case "read":
            return "Read failed."
        case "ls":
            return "List failed."
        case "webSearch":
            return "Web search failed."
        case "calendar":
            return "Calendar failed."
        case "clipboard":
            return "Clipboard failed."
        case "appControl":
            return "App control failed."
        case "mediaControl":
            return "Media control failed."
        case "pomodoro":
            return "Timer control failed."
        case "exec":
            return "Command failed."
        default:
            return "Tool failed."
        }
    }

    func postToolAction(
        label: String,
        icon: String,
        showsInOverlay: Bool = true,
        autoClearAfter: TimeInterval? = 3
    ) {
        toastClearTask?.cancel()
        lastToolAction = ToolActionToast(label: label, icon: icon, showsInOverlay: showsInOverlay)

        guard let autoClearAfter else { return }

        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(autoClearAfter))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self?.lastToolAction = nil
            }
        }
    }
}
