import Foundation
import AppKit
import NotchTooling

extension GeminiLiveSession {
    func handleFunctionCall(_ call: [String: Any]) {
        guard let name = call["name"] as? String,
              let id = call["id"] as? String else { return }

        GeminiLiveToolLogging.debug("called tool \(name) with args \(call["args"] ?? [:])")
        NotchLog.gemini.info("handleFunctionCall: name=\(name)")

        switch name {
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
        case "calendar":
            handleCalendarCall(id: id, call: call)
        case "browserControl":
            handleBrowserControlCall(id: id, call: call)

        case "pomodoro":
            handlePomodoroCall(id: id, call: call)
        case "appControl":
            handleAppControlCall(id: id, call: call)
        case "mediaControl":
            handleMediaControlCall(id: id, call: call)
        case "clipboard":
            handleClipboardCall(id: id, call: call)
        case "screenshot":
            handleScreenshotCall(id: id, call: call)
        case "memory":
            handleMemoryCall(id: id, call: call)
        default:
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
        }
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
        let resolvedTimeout = min(max(timeoutSeconds ?? 15, 1), 600)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWorkingDirectory = GeminiLiveStoragePaths
            .resolvedExecWorkingDirectory(from: workingDirectory)?
            .path

        if onShouldAutoApproveExec?(trimmedCommand, resolvedWorkingDirectory) == true {
            notifyFunctionStarted(name: name, args: args)
            let sendableArgs = SendableToolArgs(args: args)
            Task {
                let result = await executeExec(command: trimmedCommand, workingDirectory: resolvedWorkingDirectory, timeoutSeconds: resolvedTimeout)
                notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                sendFunctionResponse(id: id, name: name, result: result)
            }
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
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeReadFile(path: path, offset: offset, limit: limit)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
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

        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeWriteFile(path: path, content: content)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
    }

    private func handleLsCall(id: String, call: [String: Any]) {
        let name = "ls"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)

        let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["path"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeLs(path: path, limit: limit)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
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
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeFind(pattern: pattern, path: path, limit: limit)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
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
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeGrep(
                pattern: pattern,
                path: path,
                glob: glob,
                ignoreCase: ignoreCase,
                literal: literal,
                context: context,
                limit: limit
            )
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
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

        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeEditFile(path: path, edits: edits)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
    }

    private func handleCalendarCall(id: String, call: [String: Any]) {
        let name = "calendar"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)

        let action = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["action"]) ?? "list"
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeCalendar(action: action, args: sendableArgs.args)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
    }

    private func handleBrowserControlCall(id: String, call: [String: Any]) {
        let name = "browserControl"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)

        let action = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["action"]) ?? "open"
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                let result = await self.executeBrowserControl(action: action, args: sendableArgs.args)
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    func approveExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        notifyFunctionStarted(name: "exec", args: pending.args)
        let sendableArgs = SendableToolArgs(args: pending.args)
        Task {
            let result = await executeExec(
                command: pending.command,
                workingDirectory: pending.workingDirectory,
                timeoutSeconds: pending.timeoutSeconds
            )
            notifyFunctionExecuted(name: "exec", args: sendableArgs.args, result: result)
            sendFunctionResponse(id: toolCallID, name: "exec", result: result)
        }
    }


    private func handlePomodoroCall(id: String, call: [String: Any]) {
        let name = "pomodoro"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "status"
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            
            Task {
                var cmd = "notchctl focus \(action) pomodoro"
                if action == "start" || action == "set" {
                    if let d = rawArgs["focusDuration"] as? String { cmd += " \(d)" }
                    if let b = rawArgs["breakDuration"] as? String { cmd += " \(b)" }
                    if let l = rawArgs["longBreakDuration"] as? String { cmd += " \(l)" }
                    if let c = rawArgs["cycleCount"] as? NSNumber { cmd += " \(c)" }
                }
                let result = await self.interceptNotchctl(cmd, workingDirectory: nil) ?? ["success": false, "error": "Pomodoro command failed"]
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleAppControlCall(id: String, call: [String: Any]) {
        let name = "appControl"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "open"
        let appName = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["appName"]) ?? ""
        let direction = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["direction"]) ?? ""
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                var cmd = "notchctl app \(action) \"\(appName)\""
                if action == "move" { cmd += " \(direction)" }
                let result = await self.interceptNotchctl(cmd, workingDirectory: nil) ?? ["success": false, "error": "App control failed"]
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleMediaControlCall(id: String, call: [String: Any]) {
        let name = "mediaControl"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "play"
        // volumeLevel may arrive as a String *or* a number from the model — handle both.
        let volumeLevel: String? = {
            if let s = rawArgs["volumeLevel"] as? String { return s }
            if let n = rawArgs["volumeLevel"] as? NSNumber { return "\(n.intValue)" }
            return nil
        }()
        let skipSeconds: String? = {
            if let s = rawArgs["skipSeconds"] as? String { return s }
            if let n = rawArgs["skipSeconds"] as? NSNumber { return "\(n.intValue)" }
            return nil
        }()
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                guard action != "volume-set" || volumeLevel != nil else {
                    let result: [String: Any] = ["success": false, "error": "volume-set requires a 'volumeLevel' argument (0-100)."]
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }
                var cmd = action == "volume-set" ? "notchctl volume set \(volumeLevel!)" :
                          action == "volume-mute" ? "notchctl volume mute" :
                          action == "volume-unmute" ? "notchctl volume unmute" :
                          "notchctl media \(action)"
                if action == "skip-forward" || action == "skip-backward" {
                    cmd += " \(skipSeconds ?? "15")"
                }
                let result = await self.interceptNotchctl(cmd, workingDirectory: nil) ?? ["success": false, "error": "Media control failed"]
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleClipboardCall(id: String, call: [String: Any]) {
        let name = "clipboard"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        
        let action = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["action"]) ?? "read"
        let text = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["text"])
        let paths = args["paths"] as? [String] ?? []
        
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                let result: [String: Any]
                switch action {
                case "read":
                    let pasteboard = NSPasteboard.general
                    let clipboardText = pasteboard.string(forType: .string) ?? ""
                    result = ["success": true, "stdout": clipboardText]
                case "write":
                    guard let textToCopy = text else {
                        result = ["success": false, "error": "Missing 'text' for 'write' action."]
                        break
                    }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(textToCopy, forType: .string)
                    result = ["success": true, "message": "Copied text to clipboard."]
                case "copy-file":
                    guard !paths.isEmpty else {
                        result = ["success": false, "error": "Missing 'paths' for 'copy-file' action."]
                        break
                    }
                    var fileURLs: [NSURL] = []
                    for path in paths {
                        let expandedPath = (path as NSString).expandingTildeInPath
                        let fileURL: URL
                        if expandedPath.hasPrefix("/") {
                            fileURL = URL(fileURLWithPath: expandedPath)
                        } else {
                            fileURL = GeminiLiveStoragePaths.defaultExecWorkingDirectory.appendingPathComponent(expandedPath)
                        }
                        
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            fileURLs.append(fileURL as NSURL)
                        }
                    }
                    
                    if fileURLs.isEmpty {
                        result = ["success": false, "error": "None of the provided paths exist."]
                    } else {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        if pasteboard.writeObjects(fileURLs) {
                            result = ["success": true, "message": "Copied \(fileURLs.count) file references to clipboard."]
                        } else {
                            result = ["success": false, "error": "Failed to write file references to clipboard."]
                        }
                    }
                default:
                    result = ["success": false, "error": "Unknown clipboard action '\(action)'."]
                }
                
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleScreenshotCall(id: String, call: [String: Any]) {
        let name = "screenshot"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let mode = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["mode"]) ?? "interactive-region"
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                let cmd = "notchctl screen \(mode)"
                let result = await self.interceptNotchctl(cmd, workingDirectory: nil) ?? ["success": false, "error": "Screenshot failed"]
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleMemoryCall(id: String, call: [String: Any]) {
        let name = "memory"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "read-user"
        let contentStr = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["content"]) ?? ""
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                var result: [String: Any] = ["success": false, "error": "Unknown memory action"]
                switch action {
                case "read-user":
                    result = ["success": true, "content": self.onReadUserStore?() ?? ""]
                case "read-memory":
                    result = ["success": true, "content": self.onReadMemoryStore?() ?? ""]
                case "write-user":
                    let ok = await self.onWriteUserStore?(contentStr) ?? false
                    result = ["success": ok, "message": ok ? "User profile updated." : "Failed to update user profile."]
                case "write-memory":
                    let ok = await self.onWriteMemoryStore?(contentStr) ?? false
                    result = ["success": ok, "message": ok ? "Memory updated." : "Failed to update memory."]
                default:
                    break
                }
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    func denyExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        let result: [String: Any] = [
            "success": false,
            "error": "Command not approved by user."
        ]
        notifyFunctionExecuted(name: "exec", args: pending.args, result: result)
        sendFunctionResponse(id: toolCallID, name: "exec", result: result)
    }
}

struct SendableToolArgs: @unchecked Sendable {
    let args: [String: Any]
}
