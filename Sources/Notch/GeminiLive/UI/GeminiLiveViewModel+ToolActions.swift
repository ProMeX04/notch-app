import Foundation
import SwiftUI

extension GeminiLiveViewModel {
    func startedToolAction(for name: String) -> ToolActionToast? {
        switch name {
        case "webSearch":
            return ToolActionToast(label: "Searching web…", icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: "Reading file…", icon: "doc.text", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listing files…", icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: "Using clipboard…", icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: "Controlling app…", icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: "Controlling media…", icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: "Controlling timer…", icon: "timer", showsInOverlay: false)
        case "browserControl":
            return ToolActionToast(label: "Using browser…", icon: "safari", showsInOverlay: false)
        case "localFileSearch":
            return ToolActionToast(label: "Searching files…", icon: "doc.text.magnifyingglass", showsInOverlay: false)
        case "memory":
            return ToolActionToast(label: "Using memory…", icon: "brain", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Running command…", icon: "terminal", showsInOverlay: false)
        case "skillWriter":
            return ToolActionToast(label: "Skill writer pending approval…", icon: "wand.and.rays.inverse", showsInOverlay: false)
        default:
            return nil
        }
    }

    func completedToolAction(for name: String, success: Bool, error: String?, message: String?) -> ToolActionToast? {
        if !success {
            let label = error ?? message ?? failedToolActionLabel(for: name)
            return ToolActionToast(label: label, icon: "exclamationmark.triangle", showsInOverlay: false)
        }

        switch name {
        case "webSearch":
            return ToolActionToast(label: "Web search", icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: "Read file", icon: "doc.text", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listed files", icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: "Clipboard", icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: "App controlled", icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: "Media controlled", icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: "Timer controlled", icon: "timer", showsInOverlay: false)
        case "browserControl":
            return ToolActionToast(label: "Browser action", icon: "safari", showsInOverlay: false)
        case "localFileSearch":
            return ToolActionToast(label: "File search", icon: "doc.text.magnifyingglass", showsInOverlay: false)
        case "memory":
            return ToolActionToast(label: "Memory updated", icon: "brain", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Command executed", icon: "terminal", showsInOverlay: false)
        case "skillWriter":
            return ToolActionToast(label: message ?? "Skill saved", icon: "wand.and.rays.inverse", showsInOverlay: false)
        default:
            return nil
        }
    }

    private func failedToolActionLabel(for name: String) -> String {
        switch name {
        case "read":
            return "Read failed."
        case "ls":
            return "List failed."
        case "webSearch":
            return "Web search failed."
        case "clipboard":
            return "Clipboard failed."
        case "appControl":
            return "App control failed."
        case "mediaControl":
            return "Media control failed."
        case "pomodoro":
            return "Timer control failed."
        case "browserControl":
            return "Browser control failed."
        case "localFileSearch":
            return "File search failed."
        case "memory":
            return "Memory failed."
        case "exec":
            return "Command failed."
        case "skillWriter":
            return "Skill writer failed."
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
