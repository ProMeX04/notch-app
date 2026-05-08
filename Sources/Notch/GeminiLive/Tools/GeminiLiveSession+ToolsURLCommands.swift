@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    // MARK: - URL-Scheme Commands (media, focus, talk, panel, etc.)

    /// Build a `notch://` URL and route it through the in-process command handler.
    func handleNotchURLCommand(domain: String, tokens: [String]) async -> [String: Any] {
        guard let action = tokens.first else {
            return ["success": false, "error": "Missing action for '\(domain)'."]
        }

        // Build query parameters from remaining tokens based on domain-specific patterns
        var urlString = "notch://\(domain)/\(action)"
        let queryParams = buildQueryParams(domain: domain, action: action, tokens: Array(tokens.dropFirst()))
        if !queryParams.isEmpty {
            let queryString = queryParams.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
            urlString += "?\(queryString)"
        }

        // Route through the in-process handler if available
        if let handler = onNotchCommand, await handler(urlString) {
            return [
                "success": true,
                "message": "Command executed in-process.",
            ]
        }

        // Fallback: should not happen if ViewModel is wired up
        return ["success": false, "error": "Notch command handler not available."]
    }

    /// Build query parameters for URL-scheme commands based on domain-specific patterns.
    private func buildQueryParams(domain: String, action: String, tokens: [String]) -> [String: String] {
        var params: [String: String] = [:]

        switch domain {
        case "media":
            if action == "volume", let level = tokens.first {
                params["level"] = level
            } else if (action == "skip-forward" || action == "skip-backward"), let secs = tokens.first {
                params["seconds"] = secs
            }

        case "focus":
            switch action {
            case "show", "pause", "resume", "toggle", "reset", "skip":
                if let tool = tokens.first, tool == "pomodoro" {
                    params["tool"] = "pomodoro"
                }
            case "set", "start":
                var remaining = tokens
                if remaining.first == "pomodoro" {
                    params["tool"] = "pomodoro"
                    remaining.removeFirst()
                }
                if let d = remaining.first { params["duration"] = d; remaining.removeFirst() }
                if let b = remaining.first { params["break"] = b; remaining.removeFirst() }
                if let l = remaining.first { params["long"] = l }
            case "phase":
                if let p = tokens.first { params["phase"] = p }
            case "long-break":
                if let d = tokens.first { params["duration"] = d }
            case "cycle":
                if let c = tokens.first { params["count"] = c }
            case "auto-breaks", "auto-pomo":
                if let s = tokens.first { params["state"] = s }
            default:
                break
            }

        default:
            break
        }

        return params
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}
