import Foundation
import AppKit
import NotchGeminiLiveCore
import NotchGeminiSkillStorage
import NotchTooling

extension GeminiLiveSession {
    func handleFunctionCall(_ call: [String: Any]) {
        guard let name = call["name"] as? String,
              let id = call["id"] as? String else { return }

        let argKeys = (call["args"] as? [String: Any])?.keys.sorted() ?? []
        GeminiLiveToolLogging.debug("called tool \(name) id=\(id) argKeys=\(argKeys)")
        NotchLog.gemini.info("handleFunctionCall: name=\(name)")

        switch name {
        case GeminiLiveToolName.read:
            handleReadCall(id: id, call: call)
        case GeminiLiveToolName.exec:
            handleExecCall(id: id, call: call)
        case GeminiLiveToolName.calendar:
            handleCalendarCall(id: id, call: call)
        case GeminiLiveToolName.browserControl:
            handleBrowserControlCall(id: id, call: call)
        case GeminiLiveToolName.localFileSearch:
            handleLocalFileSearchCall(id: id, call: call)
        case GeminiLiveToolName.pomodoro:
            handlePomodoroCall(id: id, call: call)
        case GeminiLiveToolName.appControl:
            handleAppControlCall(id: id, call: call)
        case GeminiLiveToolName.mediaControl:
            handleMediaControlCall(id: id, call: call)
        case GeminiLiveToolName.clipboard:
            handleClipboardCall(id: id, call: call)
        case GeminiLiveToolName.memory:
            handleMemoryCall(id: id, call: call)
        case GeminiLiveToolName.appleMail:
            handleAppleMailCall(id: id, call: call)
        case GeminiLiveToolName.skillWriter:
            handleSkillWriterCall(id: id, call: call)
        default:
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
        }
    }

    private func handleExecCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.exec
        guard let args = call["args"] as? [String: Any],
              let command = args["command"] as? String else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let workingDirectory = args["workingDirectory"] as? String
        let timeoutSeconds = (args["timeoutSeconds"] as? NSNumber)?.doubleValue
            ?? (args["timeoutSeconds"] as? Double)
        let resolvedTimeout = min(max(timeoutSeconds ?? 900, 1), 900)
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
        let name = GeminiLiveToolName.read
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let path = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["path"]) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Missing path parameter"])
            return
        }
        let offset = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["offset"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])

        notifyFunctionStarted(name: name, args: args)
        let result = executeReadFile(path: path, offset: offset, limit: limit)
        notifyFunctionExecuted(name: name, args: args, result: result)
        sendFunctionResponse(id: id, name: name, result: result)
    }

    private func handleCalendarCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.calendar
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
        let name = GeminiLiveToolName.browserControl
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
        let name = GeminiLiveToolName.pomodoro
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "status"
        let focusDuration = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["focusDuration"])
        let breakDuration = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["breakDuration"])
        let longBreakDuration = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["longBreakDuration"])
        let cycleCount = rawArgs["cycleCount"] as? NSNumber
        let cycleCountStr = cycleCount.map { "\($0)" }
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            
            Task {
                if action == "status" {
                    if let fetcher = self.onReadPomodoroState {
                        let state = await fetcher()
                        if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted),
                           let jsonString = String(data: data, encoding: .utf8) {
                            let result: [String: Any] = [
                                "success": true,
                                "stdout": jsonString,
                                "stderr": "",
                                "exitCode": 0
                            ]
                            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                            self.sendFunctionResponse(id: id, name: name, result: result)
                            return
                        }
                    }
                    let result: [String: Any] = ["success": false, "error": "Pomodoro state fetcher not available."]
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }

                var tokens = [action, "pomodoro"]
                if action == "start" || action == "set" {
                    if let d = focusDuration { tokens.append(d) }
                    if let b = breakDuration { tokens.append(b) }
                    if let l = longBreakDuration { tokens.append(l) }
                    if let c = cycleCountStr { tokens.append(c) }
                }
                let result = await self.handleNotchURLCommand(domain: "focus", tokens: tokens)
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleAppControlCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.appControl
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "open"
        let appName = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["appName"]) ?? ""
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                let result = await self.handleAppCommand([action, appName])
                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }

    private func handleMediaControlCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.mediaControl
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
                // Read-only queries: call directly, skip notchctl string roundtrip
                if action == "status" {
                    let result: [String: Any]
                    if let fetcher = self.onReadMediaState {
                        result = await fetcher()
                    } else {
                        result = ["success": false, "error": "Media state fetcher not available."]
                    }
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }
                if action == "volume-get" {
                    let result = self.handleVolumeCommand(["get"])
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }

                // Volume set: handle natively (system output mute is not exposed via this tool)
                if action == "volume-set" {
                    guard let level = volumeLevel else {
                        let result: [String: Any] = ["success": false, "error": "volume-set requires a 'volumeLevel' argument (0-100)."]
                        self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                        self.sendFunctionResponse(id: id, name: name, result: result)
                        return
                    }
                    let result = self.handleVolumeCommand(["set", level])
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }
                let unsupportedMuteActions: Set<String> = ["mute", "unmute", "volume-mute", "volume-unmute"]
                if unsupportedMuteActions.contains(action) {
                    let result: [String: Any] = [
                        "success": false,
                        "error": "System output mute is not supported by mediaControl. Use volume-get and volume-set (0–100)."
                    ]
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                    return
                }

                // Playback actions: route directly via onMediaCommand
                var params: [String: String] = [:]
                if action == "skip-forward" || action == "skip-backward" {
                    params["seconds"] = skipSeconds ?? "15"
                }
                if let handler = self.onMediaCommand {
                    let success = await handler(action, params)
                    let result: [String: Any] = success
                        ? ["success": true]
                        : ["success": false, "error": "Media command '\(action)' failed."]
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                } else {
                    let result: [String: Any] = ["success": false, "error": "Media command handler not available."]
                    self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                    self.sendFunctionResponse(id: id, name: name, result: result)
                }
            }
        }
    }

    private func handleClipboardCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.clipboard
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
                var result: [String: Any]
                var clipboardResultItems: [AgentResultItem] = []
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

                    let batchId = UUID()
                    clipboardResultItems = [AgentResultItem(
                        batchId: batchId,
                        title: "Copied text",
                        kind: .text(textToCopy),
                        isTemporaryAsset: false
                    )]
                    result = [
                        "success": true,
                        "message": "Copied text to clipboard.",
                        "batchId": batchId.uuidString,
                        "count": clipboardResultItems.count
                    ]
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
                            let batchId = UUID()
                            clipboardResultItems = fileURLs.map { nsURL in
                                AgentResultItem(
                                    batchId: batchId,
                                    title: nil,
                                    kind: .file(nsURL as URL),
                                    isTemporaryAsset: false
                                )
                            }
                            result = [
                                "success": true,
                                "message": "Copied \(fileURLs.count) file references to clipboard.",
                                "batchId": batchId.uuidString,
                                "count": clipboardResultItems.count
                            ]
                        } else {
                            result = ["success": false, "error": "Failed to write file references to clipboard."]
                        }
                    }
                default:
                    result = ["success": false, "error": "Unknown clipboard action '\(action)'."]
                }

                if !clipboardResultItems.isEmpty {
                    await MainActor.run {
                        AgentResultStore.shared.appendBatch(clipboardResultItems)
                    }
                }

                self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
            }
        }
    }


    private func handleMemoryCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.memory
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

    private func handleLocalFileSearchCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.localFileSearch
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        guard let query = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["query"]) else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Missing required field: query"])
            return
        }
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        let scope = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["scope"])
        let kind = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["kind"])
        let sendableArgs = SendableToolArgs(args: args)
        
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeLocalFileSearch(query: query, limit: limit, scope: scope, kind: kind)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
    }

    func denyExecCall(toolCallID: String) {
        guard let pending = takePendingExecApproval(toolCallID: toolCallID) else { return }
        let result: [String: Any] = [
            "success": false,
            "error": "Command not approved by user."
        ]
        notifyFunctionExecuted(name: GeminiLiveToolName.exec, args: pending.args, result: result)
        sendFunctionResponse(id: toolCallID, name: GeminiLiveToolName.exec, result: result)
    }

    private func handleAppleMailCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.appleMail
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        
        let action = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["action"]) ?? "list_recent"
        let query = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["query"])
        let limit = GeminiToolArgumentNormalizer.intValue(in: args, keys: ["limit"])
        let messageId = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["messageId"])
        
        let sendableArgs = SendableToolArgs(args: args)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            let result = self.executeAppleMailSearch(action: action, query: query, limit: limit, messageId: messageId)
            self.notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }
    }

    private func handleSkillWriterCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.skillWriter
        guard let rawArgs = call["args"] as? [String: Any] else {
            sendFunctionResponse(id: id, name: name, result: ["error": "Unknown function or missing parameters"])
            return
        }
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        let actionRaw = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["action"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard let action = SkillWriterToolAction(rawValue: actionRaw) else {
            sendFunctionResponse(id: id, name: name, result: ["success": false, "error": "Invalid action; use create or update."])
            return
        }
        let skillId = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["skillId", "skill_id", "id"])
        if action == .update, (skillId?.isEmpty ?? true) {
            sendFunctionResponse(id: id, name: name, result: ["success": false, "error": "update requires skillId."])
            return
        }
        let skillName = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["name"]) ?? ""
        let description = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["description"]) ?? ""
        let instructions = GeminiToolArgumentNormalizer.stringValue(in: args, keys: ["instructions"]) ?? ""
        let draft = SkillDraft(name: skillName, description: description, category: "general", instructions: instructions)
        let records = skillDraftValidationRecordsProvider?() ?? []
        let excludingRecordID = action == .update ? skillId : nil
        let validation = SkillDraftValidator.validate(
            draft: draft,
            existingRecords: records,
            excludingRecordID: excludingRecordID,
            requireNonEmptyInstructions: true
        )
        if case let .failure(err) = validation {
            sendFunctionResponse(id: id, name: name, result: ["success": false, "error": err.errorDescription ?? "Validation failed."])
            return
        }
        let pending = PendingSkillWriterCall(
            toolCallID: id,
            args: args,
            action: action,
            draft: draft,
            existingSkillID: skillId
        )
        enqueuePendingSkillWriterApproval(pending)
        let previewLimit = 900
        let previewBody: String
        if draft.instructions.count > previewLimit {
            previewBody = String(draft.instructions.prefix(previewLimit)) + "\n…"
        } else {
            previewBody = draft.instructions
        }
        let summary: String
        switch action {
        case .create:
            summary = "Allow saving a new skill named \"\(draft.name)\"?"
        case .update:
            summary = "Allow updating skill \"\(draft.name)\" (\(skillId ?? "missing id"))?"
        }
        onSkillWriterApprovalRequested?(SkillWriterApprovalRequest(toolCallID: id, summary: summary, preview: previewBody))
    }
}

struct SendableToolArgs: @unchecked Sendable {
    let args: [String: Any]
}
