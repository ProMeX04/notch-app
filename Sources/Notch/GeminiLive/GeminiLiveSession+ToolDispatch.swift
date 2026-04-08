import Foundation
import NotchTooling

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
        case "ls":
            handleLsCall(id: id, call: call)
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
        notifyFunctionStarted(name: name, args: args)
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
            notifyFunctionStarted(name: name, args: args)
            let result = executeExec(command: trimmedCommand, workingDirectory: resolvedWorkingDirectory, timeoutSeconds: resolvedTimeout)
            notifyFunctionExecuted(name: name, args: args, result: result)
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
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: GeminiToolArgumentNormalizer.pathKeys) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let offset = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["offset"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        notifyFunctionStarted(name: name, args: args)
        let result = executeReadFile(path: path, offset: offset, limit: limit)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleWriteCall(id: String, call: [String: Any]) {
        let name = "write"
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: GeminiToolArgumentNormalizer.pathKeys),
              let content = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["content"], allowEmpty: true) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        notifyFunctionStarted(name: name, args: args)
        let result = executeWriteFile(path: path, content: content)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleLsCall(id: String, call: [String: Any]) {
        let name = "ls"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)

        let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["path"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        notifyFunctionStarted(name: name, args: args)
        let result = executeLs(path: path, limit: limit)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleFindCall(id: String, call: [String: Any]) {
        let name = "find"
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let pattern = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["pattern"]) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["path"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        notifyFunctionStarted(name: name, args: args)
        let result = executeFind(pattern: pattern, path: path, limit: limit)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleGrepCall(id: String, call: [String: Any]) {
        let name = "grep"
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let pattern = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["pattern"]) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let path = args["path"] as? String
        let glob = args["glob"] as? String
        let ignoreCase = GeminiToolArgumentNormalizer.boolValue(in: args, keys: ["ignoreCase"]) ?? false
        let literal = GeminiToolArgumentNormalizer.boolValue(in: args, keys: ["literal"]) ?? false
        let context = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["context"]) ?? 0
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"]) ?? 100
        notifyFunctionStarted(name: name, args: args)
        let result = executeGrep(
            pattern: pattern,
            path: path,
            glob: glob,
            ignoreCase: ignoreCase,
            literal: literal,
            context: context,
            limit: limit
        )
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleEditCall(id: String, call: [String: Any]) {
        let name = "edit"
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: GeminiToolArgumentNormalizer.pathKeys) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }

        let edits = GeminiToolArgumentNormalizer.editReplacements(in: args)
        guard !edits.isEmpty else {
            sendFunctionResponse(
                id: id,
                name: name,
                result: ["success": false, "error": "Edit tool input is invalid. edits must contain at least one replacement."]
            )
            return
        }

        notifyFunctionStarted(name: name, args: args)
        let result = executeEditFile(path: path, edits: edits)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    func approveExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        notifyFunctionStarted(name: "exec", args: pending.args)
        let result = executeExec(
            command: pending.command,
            workingDirectory: pending.workingDirectory,
            timeoutSeconds: pending.timeoutSeconds
        )
        notifyFunctionExecuted(name: "exec", args: pending.args, result: result)
        sendFunctionResponse(id: toolCallID, name: "exec", result: result)
    }

    func denyExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        let result: [String: Any] = [
            "success": false,
            "command": pending.command,
            "error": "Command not approved by user."
        ]
        notifyFunctionExecuted(name: "exec", args: pending.args, result: result)
        sendFunctionResponse(id: toolCallID, name: "exec", result: result)
    }
}
