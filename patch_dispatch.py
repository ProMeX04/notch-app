import re

file_path = "Sources/Notch/GeminiLive/GeminiLiveSession+ToolDispatch.swift"
with open(file_path, "r") as f:
    content = f.read()

# Add cases
cases_to_add = """
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
        default:"""
content = content.replace("        default:", cases_to_add)

# Add methods before `    func denyExecCall`
methods = """
    private func handlePomodoroCall(id: String, call: [String: Any]) {
        let name = "pomodoro"
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "status"
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            
            Task {
                var cmd = "notchctl focus \\(action) pomodoro"
                if action == "start" || action == "set" {
                    if let d = rawArgs["focusDuration"] as? String { cmd += " \\(d)" }
                    if let b = rawArgs["breakDuration"] as? String { cmd += " \\(b)" }
                    if let l = rawArgs["longBreakDuration"] as? String { cmd += " \\(l)" }
                    if let c = rawArgs["cycleCount"] as? NSNumber { cmd += " \\(c)" }
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
                var cmd = "notchctl app \\(action) \\"\\(appName)\\""
                if action == "move" { cmd += " \\(direction)" }
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
        let volumeLevel = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["volumeLevel"])
        let skipSeconds = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["skipSeconds"])
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                var cmd = action == "volume-set" ? "notchctl volume set \\(volumeLevel ?? "50")" : 
                          action == "volume-mute" ? "notchctl volume mute" :
                          action == "volume-unmute" ? "notchctl volume unmute" :
                          "notchctl media \\(action)"
                if action == "skip-forward" || action == "skip-backward" {
                    cmd += " \\(skipSeconds ?? "15")"
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
        let action = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["action"]) ?? "read"
        let contentToCopy = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["contentToCopy"])
        let format = GeminiToolArgumentNormalizer.stringValue(in: rawArgs, keys: ["format"]) ?? "text"
        
        let sendableArgs = SendableToolArgs(args: rawArgs)
        toolExecutionQueue.async { [weak self] in
            guard let self else { return }
            self.notifyFunctionStarted(name: name, args: sendableArgs.args)
            Task {
                var result: [String: Any] = ["success": false, "error": "Unknown clipboard action"]
                if action == "read" {
                    result = await self.interceptNotchctl("notchctl clipboard read", workingDirectory: nil) ?? result
                } else if action == "write" {
                    // For write, notchctl clipboard write expects stdin, but interceptNotchctl doesn't do stdin.
                    // Let's use executeClipboard directly from Tools.swift if we write it, or write to clipboard natively.
                    // Wait, interceptNotchctl handles "clipboard write" by returning success! But it doesn't actually copy!
                    // Let's implement native copy here.
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(contentToCopy ?? "", forType: format == "html" ? .html : .string)
                    result = ["success": true, "message": "Copied \\(format) to clipboard."]
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
                let cmd = "notchctl screen \\(mode)"
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

    func denyExecCall"""
content = content.replace("    func denyExecCall", methods)

with open(file_path, "w") as f:
    f.write(content)
