import AppKit
import Foundation

extension GeminiLiveSession {
    func handleFunctionCall(_ call: [String: Any]) {
        guard let name = call["name"] as? String,
              let id = call["id"] as? String else { return }

        GeminiLiveToolLogging.debug("called tool \(name) with args \(call["args"] ?? [:])")

        switch name {
        case "controlApp":
            handleControlAppCall(id: id, call: call)
        case "controlBrowser":
            handleControlBrowserCall(id: id, call: call)
        case "controlTimer":
            handleControlTimerCall(id: id, call: call)
        case "controlMedia":
            handleControlMediaCall(id: id, call: call)
        case "readClipboard":
            handleReadClipboardCall(id: id, call: call)
        case "manageNotes":
            handleManageNotesCall(id: id, call: call)
        case "controlVolume":
            handleControlVolumeCall(id: id, call: call)
        case "displayImage":
            handleDisplayImageCall(id: id, call: call)
        case "webSearch":
            handleWebSearchCall(id: id, call: call)
        default:
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
        }
    }

    private func handleControlAppCall(id: String, call: [String: Any]) {
        let name = "controlApp"
        guard let args = call["args"] as? [String: Any],
              let appName = args["appName"] as? String,
              let action = args["action"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let result = executeControlApp(appName: appName, action: action)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleControlBrowserCall(id: String, call: [String: Any]) {
        let name = "controlBrowser"
        guard let args = call["args"] as? [String: Any],
              let action = args["action"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let url = args["url"] as? String
        let query = args["query"] as? String
        let result = executeControlBrowser(action: action, url: url, query: query)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleControlTimerCall(id: String, call: [String: Any]) {
        let name = "controlTimer"
        guard let args = call["args"] as? [String: Any],
              let timerName = args["timer"] as? String,
              let action = args["action"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let duration = args["duration"] as? String
        let breakDuration = args["breakDuration"] as? String
        let minutes = (args["minutes"] as? NSNumber)?.intValue ?? (args["minutes"] as? Int)
        let breakMinutes = (args["breakMinutes"] as? NSNumber)?.intValue ?? (args["breakMinutes"] as? Int)
        let message = onTimerControl?(timerName, action, duration, breakDuration, minutes, breakMinutes) ?? "Timer control not available"
        let result: [String: Any] = ["success": true, "message": message]
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleControlMediaCall(id: String, call: [String: Any]) {
        let name = "controlMedia"
        guard let args = call["args"] as? [String: Any],
              let action = args["action"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let value = (args["value"] as? NSNumber)?.doubleValue ?? args["value"] as? Double
        let valueString = args["valueString"] as? String
        let message = onMediaControl?(action, value, valueString) ?? "Media control not available"
        let result: [String: Any] = ["success": true, "message": message]
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleReadClipboardCall(id: String, call: [String: Any]) {
        let name = "readClipboard"
        let result = executeReadClipboard()
        onFunctionExecuted?(name, call["args"] as? [String: Any] ?? [:], result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleManageNotesCall(id: String, call: [String: Any]) {
        let name = "manageNotes"
        guard let args = call["args"] as? [String: Any],
              let action = args["action"] as? String,
              let content = args["content"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let title = args["title"] as? String
        let result = executeManageNotes(action: action, title: title, content: content)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleControlVolumeCall(id: String, call: [String: Any]) {
        let name = "controlVolume"
        guard let args = call["args"] as? [String: Any],
              let action = args["action"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let level = (args["level"] as? NSNumber)?.intValue ?? args["level"] as? Int
        let result = executeControlVolume(action: action, level: level)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleDisplayImageCall(id: String, call: [String: Any]) {
        let name = "displayImage"
        guard let args = call["args"] as? [String: Any],
              let query = args["query"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let caption = args["caption"] as? String
        let orientation = args["orientation"] as? String
        executeDisplayImageAsync(
            id: id,
            name: name,
            args: args,
            query: query,
            caption: caption,
            orientation: orientation
        )
    }

    private func handleWebSearchCall(id: String, call: [String: Any]) {
        let name = "webSearch"
        guard let args = call["args"] as? [String: Any],
              let query = args["query"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let maxResults = (args["maxResults"] as? NSNumber)?.intValue ?? args["maxResults"] as? Int ?? 5
        executeWebSearchAsync(id: id, name: name, args: args, query: query, maxResults: maxResults)
    }
}
