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
        case "read":
            handleReadCall(id: id, call: call)
        case "write":
            handleWriteCall(id: id, call: call)
        case "exec":
            handleExecCall(id: id, call: call)
        case "find":
            handleFindCall(id: id, call: call)
        case "grep":
            handleGrepCall(id: id, call: call)
        case "edit":
            handleEditCall(id: id, call: call)
        case "readDoc":
            handleReadDocCall(id: id, call: call)
        case "writeMemory":
            handleWriteMemoryCall(id: id, call: call)
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

    private func handleExecCall(id: String, call: [String: Any]) {
        let name = "exec"
        guard let args = call["args"] as? [String: Any],
              let command = args["command"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let workingDirectory = args["workingDirectory"] as? String
        let timeoutSeconds = (args["timeoutSeconds"] as? NSNumber)?.doubleValue
            ?? (args["timeoutSeconds"] as? Double)
        let resolvedTimeout = min(max(timeoutSeconds ?? 15, 1), 30)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWorkingDirectory = GeminiLiveStoragePaths
            .resolvedExecWorkingDirectory(from: workingDirectory)?
            .path

        if onShouldAutoApproveExec?(trimmedCommand, resolvedWorkingDirectory) == true {
            let result = executeExec(command: trimmedCommand, workingDirectory: resolvedWorkingDirectory, timeoutSeconds: resolvedTimeout)
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        enqueuePendingExecApproval(
            PendingExecApprovalCall(
                toolCallID: id,
                args: args,
                command: trimmedCommand,
                workingDirectory: resolvedWorkingDirectory,
                timeoutSeconds: resolvedTimeout
            )
        )
        onExecApprovalRequested?(
            ExecApprovalRequest(
                toolCallID: id,
                command: trimmedCommand,
                workingDirectory: resolvedWorkingDirectory,
                timeoutSeconds: resolvedTimeout
            )
        )
    }

    private func handleReadCall(id: String, call: [String: Any]) {
        let name = "read"
        guard let args = call["args"] as? [String: Any],
              let path = args["path"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let result = executeReadFile(path: path)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleWriteCall(id: String, call: [String: Any]) {
        let name = "write"
        guard let args = call["args"] as? [String: Any],
              let path = args["path"] as? String,
              let content = args["content"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let result = executeWriteFile(path: path, content: content)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleFindCall(id: String, call: [String: Any]) {
        let name = "find"
        guard let args = call["args"] as? [String: Any],
              let pattern = args["pattern"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let baseDirectory = args["baseDirectory"] as? String
        let maxResults = (args["maxResults"] as? NSNumber)?.intValue ?? args["maxResults"] as? Int
        let result = executeFindFiles(pattern: pattern, baseDirectory: baseDirectory, maxResults: maxResults)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleGrepCall(id: String, call: [String: Any]) {
        let name = "grep"
        guard let args = call["args"] as? [String: Any],
              let pattern = args["pattern"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let path = args["path"] as? String
        let maxResults = (args["maxResults"] as? NSNumber)?.intValue ?? args["maxResults"] as? Int
        let result = executeGrep(pattern: pattern, path: path, maxResults: maxResults)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleEditCall(id: String, call: [String: Any]) {
        let name = "edit"
        guard let args = call["args"] as? [String: Any],
              let path = args["path"] as? String,
              let oldText = args["oldText"] as? String,
              let newText = args["newText"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let replaceAll = (args["replaceAll"] as? NSNumber)?.boolValue ?? args["replaceAll"] as? Bool ?? false
        let result = executeEditFile(path: path, oldText: oldText, newText: newText, replaceAll: replaceAll)
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleReadDocCall(id: String, call: [String: Any]) {
        let name = "readDoc"
        guard let args = call["args"] as? [String: Any],
              let rawKind = args["kind"] as? String,
              let kind = ReadDocKind(rawValue: rawKind),
              let documentID = args["id"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let result = onReadDocument?(kind, documentID, currentConfiguration?.skillSnapshot)
            ?? ["success": false, "error": "Document reading is not available."]
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleWriteMemoryCall(id: String, call: [String: Any]) {
        let name = "writeMemory"
        guard let args = call["args"] as? [String: Any],
              let content = args["content"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let result = onWriteMemory?(content)
            ?? ["success": false, "error": "Memory writing is not available."]
        onFunctionExecuted?(name, args, result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    func approveExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        let result = executeExec(
            command: pending.command,
            workingDirectory: pending.workingDirectory,
            timeoutSeconds: pending.timeoutSeconds
        )
        onFunctionExecuted?("exec", pending.args, result)
        sendFunctionResponse(id: toolCallID, name: "exec", result: result)
    }

    func denyExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        let result: [String: Any] = [
            "success": false,
            "command": pending.command,
            "error": "Command not approved by user."
        ]
        onFunctionExecuted?("exec", pending.args, result)
        sendFunctionResponse(id: toolCallID, name: "exec", result: result)
    }
}
