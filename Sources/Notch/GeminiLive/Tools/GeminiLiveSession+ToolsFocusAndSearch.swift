@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
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
    func executeBrowserControl(action: String, args: [String: Any]) async -> [String: Any] {
        NotchLog.gemini.info("executeBrowserControl called: action=\(action)")
        
        guard let handler = onBrowserBridgeCommand else {
            NotchLog.gemini.error("executeBrowserControl: onBrowserBridgeCommand is nil!")
            return ["success": false, "error": "Browser bridge is not available."]
        }
        
        // Check if extension is connected
        let isConnected = onBrowserBridgeIsConnected?() ?? false
        NotchLog.gemini.info("executeBrowserControl: extension connected = \(isConnected)")
        
        let bridgeResult = await handler(action, args)
        NotchLog.gemini.info("executeBrowserControl: bridgeResult isNil=\(bridgeResult == nil)")
        
        guard let bridgeResult else {
            return ["success": false, "error": "Browser extension did not respond (timeout). Make sure the Notch Focus extension is installed and enabled in Chrome."]
        }
        
        var result = bridgeResult
        if result["success"] == nil {
            result["success"] = result["error"] == nil && result["errorMessage"] == nil
        }
        
        return result
    }

    func executeLocalFileSearch(query: String, limit: Int?, scope: String?, kind: String?) -> [String: Any] {
        let manager = SpotlightManager()
        return manager.search(
            query: query,
            limit: min(max(limit ?? 10, 1), 50),
            scope: scope,
            kind: kind
        )
    }

    func executeAppleMailSearch(action: String, query: String?, limit: Int?, messageId: String? = nil) -> [String: Any] {
        let manager = MailSQLiteManager.shared
        let resolvedLimit = min(max(limit ?? 10, 1), 50)
        
        do {
            if action == "read_content" {
                guard let messageId, !messageId.isEmpty else {
                    return ["success": false, "error": "read_content requires a 'messageId'. Use 'search' or 'list_recent' first to get message IDs."]
                }

                var email = try manager.fetchEmailById(messageId: messageId)
                email["success"] = true
                return email
            }

            let results: [[String: Any]]
            if action == "search", let q = query, !q.isEmpty {
                results = try manager.searchEmails(keyword: q, limit: resolvedLimit)
            } else {
                results = try manager.fetchRecentEmails(limit: resolvedLimit)
            }

            return [
                "success": true,
                "count": results.count,
                "emails": results
            ]
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
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
