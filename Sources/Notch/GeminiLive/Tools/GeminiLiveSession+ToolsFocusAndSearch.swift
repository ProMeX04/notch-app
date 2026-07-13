@preconcurrency import Foundation
import NotchTooling

extension GeminiLiveSession {
    // MARK: - Focus Tool

    func executeFocus(args: [String: Any]) async -> [String: Any] {
        guard let action = args["action"] as? String else {
            return ["success": false, "error": "Missing required field: action"]
        }

        switch action.lowercased() {
        case "status":
            if let fetcher = onReadPomodoroState {
                return await fetcher()
            } else {
                return ["success": false, "error": "Pomodoro state fetcher not available."]
            }
        case "start", "resume", "pause", "reset", "skip", "set", "phase", "cycle", "auto_breaks", "auto_pomo":
            guard let handler = onNotchCommand else {
                return ["success": false, "error": "Pomodoro command handler not available."]
            }

            // Map tool schema actions to router actions
            let routerAction: String
            if action == "auto_breaks" {
                routerAction = "auto-breaks"
            } else if action == "auto_pomo" {
                routerAction = "auto-pomo"
            } else {
                routerAction = action
            }

            var queryItems: [String] = []
            
            if let f = args["focusDuration"] as? NSNumber { queryItems.append("duration=\(f.intValue)m") }
            if let s = args["shortBreakDuration"] as? NSNumber { queryItems.append("break=\(s.intValue)m") }
            if let l = args["longBreakDuration"] as? NSNumber { queryItems.append("long=\(l.intValue)m") }
            if let p = args["targetPhase"] as? String { queryItems.append("phase=\(p)") }
            if let c = args["count"] as? NSNumber { queryItems.append("count=\(c.intValue)") }
            if let e = args["enabled"] as? Bool { queryItems.append("state=\(e ? "on" : "off")") }

            var urlString = "notch://focus/\(routerAction)"
            if !queryItems.isEmpty {
                urlString += "?" + queryItems.joined(separator: "&")
            }

            let success = await handler(urlString)
            return [
                "success": success,
                "message": success ? "Focus command executed." : "Focus command failed.",
                "url": urlString
            ]
        default:
            return ["success": false, "error": "Unknown action '\\(action)'."]
        }
    }

    func truncatedToolOutput(_ value: String, limit: Int = 8000) -> TruncatedToolOutput {
        guard value.count > limit else {
            return TruncatedToolOutput(text: value, truncated: false, limit: limit)
        }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return TruncatedToolOutput(text: String(value[..<endIndex]) + "\n...[truncated]", truncated: true, limit: limit)
    }
}

struct ProcessResult {
    let terminationStatus: Int32?
    let stdoutText: String
    let stderrText: String
    let runError: String?
    let timedOut: Bool
}

struct TruncatedToolOutput {
    let text: String
    let truncated: Bool
    let limit: Int
}
