import Foundation

extension GeminiLiveSession {
    func handleFunctionCall(_ call: [String: Any]) {
        guard let name = call["name"] as? String,
              let id = call["id"] as? String else { return }

        GeminiLiveToolLogging.debug("called tool \(name) with args \(call["args"] ?? [:])")

        switch name {
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
        default:
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
        }
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
