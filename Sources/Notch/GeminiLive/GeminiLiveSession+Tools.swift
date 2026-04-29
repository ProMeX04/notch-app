import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    private var workspaceCodingTools: GeminiWorkspaceCodingTools {
        GeminiWorkspaceCodingTools(
            workspaceRoot: GeminiLiveStoragePaths.workspaceRoot,
            builtInSkillsDirectory: GeminiLiveStoragePaths.builtInSkillsDirectory
        )
    }

    nonisolated(unsafe) private static let calendarStore = EKEventStore()

    func sendFunctionResponse(id: String, name: String, result: [String: Any]) {
        let responsePayload = GeminiLiveToolResponsePayloadBuilder.buildToolResponsePayload(
            id: id,
            name: name,
            result: result
        )
        let transportResult = GeminiLiveToolResponsePayloadBuilder.transportResult(
            from: result,
            toolName: name
        )

        sendJSONObject(responsePayload)
        GeminiLiveToolLogging.debug("tool response sent for \(name): \(transportResult)")
    }

    func sanitizedToolResultForCallback(name: String, result: [String: Any]) -> [String: Any] {
        GeminiLiveToolResponsePayloadBuilder.transportResult(from: result, toolName: name)
    }

    func notifyFunctionStarted(name: String, args: [String: Any]) {
        onFunctionStarted?(name, args)
    }

    func notifyFunctionExecuted(name: String, args: [String: Any], result: [String: Any]) {
        onFunctionExecuted?(name, args, sanitizedToolResultForCallback(name: name, result: result))
    }

    func executeReadFile(path: String, offset: Int? = nil, limit: Int? = nil) -> [String: Any] {
        workspaceCodingTools.executeReadFile(path: path, offset: offset, limit: limit)
    }

    func executeWriteFile(path: String, content: String) -> [String: Any] {
        workspaceCodingTools.executeWriteFile(path: path, content: content)
    }

    func executeLs(path: String?, limit: Int?) -> [String: Any] {
        workspaceCodingTools.executeLs(path: path, limit: limit)
    }

    func executeFind(pattern: String, path: String?, limit: Int?) -> [String: Any] {
        workspaceCodingTools.executeFind(pattern: pattern, path: path, limit: limit)
    }

    func executeGrep(
        pattern: String,
        path: String?,
        glob: String? = nil,
        ignoreCase: Bool = false,
        literal: Bool = false,
        context: Int = 0,
        limit: Int = 100
    ) -> [String: Any] {
        workspaceCodingTools.executeGrep(
            pattern: pattern,
            path: path,
            glob: glob,
            ignoreCase: ignoreCase,
            literal: literal,
            context: context,
            limit: limit
        )
    }

    func executeEditFile(path: String, edits: [GeminiExactTextEdit]) -> [String: Any] {
        workspaceCodingTools.executeEditFile(path: path, edits: edits)
    }

    func executeExec(command: String, workingDirectory: String?, timeoutSeconds: Double?) async -> [String: Any] {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return ["success": false, "error": "Command is empty."]
        }

        // ── Intercept notchctl commands ──────────────────────────────────
        if let interceptResult = await interceptNotchctl(trimmedCommand, workingDirectory: workingDirectory) {
            return interceptResult
        }

        // ── Normal shell execution ──────────────────────────────────────
        GeminiLiveStoragePaths.prepare(fileManager: .default)
        let timeout = min(max(timeoutSeconds ?? 15, 1), 600)
        let cwd = GeminiLiveStoragePaths.resolvedExecWorkingDirectory(from: workingDirectory)
        if let cwd {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return ["success": false, "error": "Working directory does not exist: \(workingDirectory ?? cwd.path)"]
            }
        }

        let process = await runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", trimmedCommand],
            currentDirectoryURL: cwd,
            timeout: timeout
        )

        let stdout = truncatedToolOutput(process.stdoutText)
        let stderr = truncatedToolOutput(process.stderrText)
        let exitCode = Int(process.terminationStatus ?? -1)

        if let runError = process.runError {
            var result: [String: Any] = [
                "success": false,
                "command": trimmedCommand,
                "error": "Failed to start command: \(runError)"
            ]
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        if process.timedOut {
            var result: [String: Any] = [
                "success": false,
                "command": trimmedCommand,
                "error": "Command timed out after \(Int(timeout))s.",
                "exitCode": exitCode,
                "stdout": stdout,
                "stderr": stderr
            ]
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        var result: [String: Any] = [
            "success": exitCode == 0,
            "command": trimmedCommand,
            "message": exitCode == 0 ? "Command finished successfully." : "Command exited with status \(exitCode).",
            "exitCode": exitCode,
            "stdout": stdout,
            "stderr": stderr
        ]
        if let cwd {
            result["workingDirectory"] = cwd.path
        }
        return result
    }

    // MARK: - Notchctl Intercept

    /// Parse and intercept `notchctl` commands, executing them in-process instead of spawning a shell.
    private func interceptNotchctl(_ command: String, workingDirectory: String?) async -> [String: Any]? {
        // Match: ~/.notch/bin/notchctl <args...>  OR  notchctl <args...>
        let notchctlPrefixes = ["~/.notch/bin/notchctl ", "$HOME/.notch/bin/notchctl ", "notchctl "]
        var argsString: String?
        for prefix in notchctlPrefixes {
            if command.hasPrefix(prefix) {
                argsString = String(command.dropFirst(prefix.count))
                break
            }
        }
        guard let rawArgs = argsString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawArgs.isEmpty else {
            return nil
        }

        let tokens = shellTokenize(rawArgs)
        guard let domain = tokens.first else { return nil }

        switch domain {
        // ── System-level commands (handle directly in Swift) ─────────
        case "volume":
            return handleVolumeCommand(Array(tokens.dropFirst()))
        case "notes":
            return await handleNotesCommand(Array(tokens.dropFirst()))
        case "app":
            return await handleAppCommand(Array(tokens.dropFirst()))
        case "clipboard":
            return handleClipboardCommand(Array(tokens.dropFirst()), workingDirectory: workingDirectory)

        // ── Special case for focus status ────────────────────────────
        case "focus":
            let subTokens = Array(tokens.dropFirst())
            if subTokens.first == "status" {
                if let fetcher = onReadPomodoroState {
                    let state = await fetcher()
                    if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted),
                       let jsonString = String(data: data, encoding: .utf8) {
                        return [
                            "success": true,
                            "command": command,
                            "stdout": jsonString,
                            "stderr": "",
                            "exitCode": 0
                        ]
                    }
                }
                return ["success": false, "error": "Pomodoro state fetcher not available."]
            }
            // Fallthrough to URL-scheme routing for other focus commands
            return await handleNotchURLCommand(domain: domain, tokens: subTokens)

        // ── URL-scheme commands (route through NotchCommandRouter) ───
        case "panel", "visibility", "pin", "talk", "screen", "caption", "media":
            return await handleNotchURLCommand(domain: domain, tokens: Array(tokens.dropFirst()))

        default:
            return nil  // Unknown domain, fall through to shell
        }
    }

    /// Tokenize a shell command respecting quoted strings.
    private func shellTokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inDoubleQuote = false
        var inSingleQuote = false
        var escaped = false

        for char in input {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" && !inSingleQuote {
                escaped = true
                continue
            }
            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }
            if char == " " && !inDoubleQuote && !inSingleQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    // MARK: - URL-Scheme Commands (media, focus, talk, panel, etc.)

    /// Build a `notch://` URL and route it through the in-process command handler.
    private func handleNotchURLCommand(domain: String, tokens: [String]) async -> [String: Any] {
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
                "command": "notchctl \(domain) \(tokens.joined(separator: " "))",
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

    // MARK: - Volume (Native)

    private func handleVolumeCommand(_ tokens: [String]) -> [String: Any] {
        guard let action = tokens.first else {
            return ["success": false, "error": "Missing action for 'volume'. Use: get, set, mute, unmute."]
        }
        switch action {
        case "get":
            let script = "output volume of (get volume settings)"
            let result = runAppleScript(script)
            return ["success": true, "command": "notchctl volume get", "stdout": result]
        case "set":
            guard let levelStr = tokens.dropFirst().first else {
                return ["success": false, "error": "Missing volume level. Usage: volume set <0-100>"]
            }
            let script = "set volume output volume \(levelStr)"
            _ = runAppleScript(script)
            return ["success": true, "command": "notchctl volume set \(levelStr)", "message": "Volume set to \(levelStr)."]
        case "mute":
            _ = runAppleScript("set volume with output muted")
            return ["success": true, "command": "notchctl volume mute", "message": "Volume muted."]
        case "unmute":
            _ = runAppleScript("set volume without output muted")
            return ["success": true, "command": "notchctl volume unmute", "message": "Volume unmuted."]
        default:
            return ["success": false, "error": "Unknown volume action '\(action)'."]
        }
    }

    // MARK: - Notes (Native)

    private func handleNotesCommand(_ tokens: [String]) async -> [String: Any] {
        guard tokens.first == "create" else {
            return ["success": false, "error": "Unknown notes action. Use: notes create <text>"]
        }
        let text = Array(tokens.dropFirst()).joined(separator: " ")
        guard !text.isEmpty else {
            return ["success": false, "error": "Missing note text."]
        }
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Notes\" to make new note with properties {body:\"\(escaped)\"}"
        _ = runAppleScript(script)
        return ["success": true, "command": "notchctl notes create", "message": "Note created."]
    }

    // MARK: - App Control (Native)

    private func handleAppCommand(_ tokens: [String]) async -> [String: Any] {
        guard !tokens.isEmpty else {
            return ["success": false, "error": "Usage: app <open|quit|check|minimize|move> <name> [args]"]
        }
        let action = tokens[0]
        let argTokens = Array(tokens.dropFirst())

        func parseAppNameAndExtra() -> (appName: String, extra: [String])? {
            guard !argTokens.isEmpty else { return nil }
            if argTokens.count >= 2 {
                let trailing = argTokens.last!.lowercased()
                let knownDirections = ["left", "right", "top", "bottom", "center"]
                if knownDirections.contains(trailing) {
                    let nameTokens = Array(argTokens.dropLast())
                    if !nameTokens.isEmpty {
                        return (nameTokens.joined(separator: " "), [trailing])
                    }
                }
            }
            return (argTokens.joined(separator: " "), [])
        }

        guard let parsed = parseAppNameAndExtra() else {
            return ["success": false, "error": "Missing app name."]
        }
        let appName = parsed.appName
        let extra = parsed.extra

        switch action {
        case "open":
            let result = await runProcess(
                executablePath: "/usr/bin/open",
                arguments: ["-a", appName],
                timeout: 10
            )
            let success = result.terminationStatus == 0
            return [
                "success": success,
                "command": "notchctl app open \(appName)",
                "message": success ? "\(appName) opened." : "Failed to open \(appName).",
            ]
        case "quit":
            let script = "tell application \"\(appName)\" to quit"
            _ = runAppleScript(script)
            return ["success": true, "command": "notchctl app quit \(appName)", "message": "\(appName) quit."]
        case "check":
            let result = await runProcess(
                executablePath: "/usr/bin/pgrep",
                arguments: ["-x", appName],
                timeout: 5
            )
            let running = result.terminationStatus == 0
            return [
                "success": true,
                "command": "notchctl app check \(appName)",
                "stdout": running ? "running" : "not running",
            ]
        case "minimize":
            let script = """
            tell application "\(appName)"
                try
                    set miniaturized of front window to true
                    return "ok"
                on error errMsg
                    return "error: " & errMsg
                end try
            end tell
            """
            let result = runAppleScriptWithStatus(script)
            let success = result.success && !result.stdout.lowercased().hasPrefix("error:")
            return [
                "success": success,
                "command": "notchctl app minimize \(appName)",
                "message": success ? "\(appName) minimized." : "Failed to minimize \(appName).",
                "stderr": result.errorMessage ?? ""
            ]
        case "move":
            guard let direction = extra.first else {
                return ["success": false, "error": "Usage: app move <name> <left|right|top|bottom|center>"]
            }
            let script = """
            set targetDirection to "\(direction)"
            set padding to 12
            tell application "Finder" to set desktopBounds to bounds of window of desktop
            set screenLeft to item 1 of desktopBounds
            set screenTop to item 2 of desktopBounds
            set screenRight to item 3 of desktopBounds
            set screenBottom to item 4 of desktopBounds
            set screenWidth to screenRight - screenLeft
            set screenHeight to screenBottom - screenTop

            tell application "\(appName)"
                activate
                if (count of windows) = 0 then
                    return "error: no window"
                end if
            end tell

            tell application "System Events"
                tell process "\(appName)"
                    set targetWindow to front window
                    try
                        set isFullscreen to value of attribute "AXFullScreen" of targetWindow
                    on error
                        set isFullscreen to false
                    end try
                    if isFullscreen is true then
                        try
                            set value of attribute "AXFullScreen" of targetWindow to false
                        on error
                            keystroke "f" using {command down, control down}
                        end try
                        repeat with i from 1 to 25
                            delay 0.1
                            try
                                if (value of attribute "AXFullScreen" of targetWindow) is false then
                                    exit repeat
                                end if
                            on error
                                exit repeat
                            end try
                        end repeat
                    end if
                end tell
            end tell

            set targetWidth to (screenWidth * 0.5) as integer
            set targetHeight to (screenHeight * 0.8) as integer
            set targetX to screenLeft + ((screenWidth - targetWidth) / 2)
            set targetY to screenTop + ((screenHeight - targetHeight) / 2)

            if targetDirection is "left" then
                set targetWidth to (screenWidth / 2) as integer
                set targetHeight to (screenHeight - (padding * 2)) as integer
                set targetX to screenLeft + padding
                set targetY to screenTop + padding
            else if targetDirection is "right" then
                set targetWidth to (screenWidth / 2) as integer
                set targetHeight to (screenHeight - (padding * 2)) as integer
                set targetX to screenLeft + (screenWidth / 2)
                set targetY to screenTop + padding
            else if targetDirection is "top" then
                set targetWidth to (screenWidth - (padding * 2)) as integer
                set targetHeight to (screenHeight / 2) as integer
                set targetX to screenLeft + padding
                set targetY to screenTop + padding
            else if targetDirection is "bottom" then
                set targetWidth to (screenWidth - (padding * 2)) as integer
                set targetHeight to (screenHeight / 2) as integer
                set targetX to screenLeft + padding
                set targetY to screenTop + (screenHeight / 2)
            else if targetDirection is "center" then
                set targetWidth to (screenWidth * 0.7) as integer
                set targetHeight to (screenHeight * 0.8) as integer
                set targetX to screenLeft + ((screenWidth - targetWidth) / 2)
                set targetY to screenTop + ((screenHeight - targetHeight) / 2)
            else
                return "error: invalid direction"
            end if

            tell application "System Events"
                tell process "\(appName)"
                    set targetWindow to front window
                    try
                        set position of targetWindow to {targetX, targetY}
                        set size of targetWindow to {targetWidth, targetHeight}
                        return "ok"
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end tell
            end tell
            """
            let result = runAppleScriptWithStatus(script)
            let success = result.success && !result.stdout.lowercased().hasPrefix("error:")
            return [
                "success": success,
                "command": "notchctl app move \(appName) \(direction)",
                "message": success ? "\(appName) moved \(direction)." : "Failed to move \(appName) \(direction).",
                "stderr": result.errorMessage ?? ""
            ]
        default:
            return ["success": false, "error": "Unknown app action '\(action)'."]
        }
    }

    // MARK: - Clipboard (Native)

    private func handleClipboardCommand(_ tokens: [String], workingDirectory: String?) -> [String: Any] {
        guard let action = tokens.first else {
            return ["success": false, "error": "Missing action for 'clipboard'. Use: read, write, copy-file."]
        }
        switch action {
        case "read":
            let pasteboard = NSPasteboard.general
            let text = pasteboard.string(forType: .string) ?? ""
            return ["success": true, "command": "notchctl clipboard read", "stdout": text]
        case "write":
            let text = Array(tokens.dropFirst()).joined(separator: " ")
            guard !text.isEmpty else {
                return ["success": false, "error": "Missing text. Usage: clipboard write <text>"]
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(text, forType: .string)
            guard didWrite else {
                return ["success": false, "error": "Failed to write text to the clipboard."]
            }
            return ["success": true, "command": "notchctl clipboard write", "message": "Copied text to clipboard."]
        case "copy-file":
            let rawPaths = Array(tokens.dropFirst()).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard !rawPaths.isEmpty else {
                return ["success": false, "error": "Missing file path. Usage: clipboard copy-file <path...>"]
            }

            var fileURLs: [NSURL] = []
            for rawPath in rawPaths {
                let expandedPath = resolvedClipboardFilePath(rawPath, workingDirectory: workingDirectory)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
                    return ["success": false, "error": "File does not exist: \(rawPath)"]
                }
                let fileURL = URL(fileURLWithPath: expandedPath, isDirectory: isDirectory.boolValue)
                fileURLs.append(fileURL as NSURL)
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects(fileURLs) else {
                return [
                    "success": false,
                    "command": "notchctl clipboard copy-file",
                    "error": rawPaths.count == 1
                        ? "Failed to copy file reference to the clipboard."
                        : "Failed to copy file references to the clipboard."
                ]
            }
            return [
                "success": true,
                "command": "notchctl clipboard copy-file",
                "message": rawPaths.count == 1
                    ? "Copied file reference to clipboard."
                    : "Copied \(rawPaths.count) file references to clipboard."
            ]
        default:
            return ["success": false, "error": "Unknown clipboard action '\(action)'."]
        }
    }

    private func resolvedClipboardFilePath(_ rawPath: String, workingDirectory: String?) -> String {
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return expandedPath
        }

        let baseDirectory = GeminiLiveStoragePaths.resolvedExecWorkingDirectory(from: workingDirectory)
            ?? GeminiLiveStoragePaths.defaultExecWorkingDirectory
        return baseDirectory.appendingPathComponent(expandedPath).path
    }

    // MARK: - AppleScript Helper

    private func runAppleScript(_ script: String) -> String {
        runAppleScriptWithStatus(script).stdout
    }

    private func runAppleScriptWithStatus(_ script: String) -> (success: Bool, stdout: String, errorMessage: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (
                success: process.terminationStatus == 0,
                stdout: stdout,
                errorMessage: (stderr?.isEmpty == false) ? stderr : nil
            )
        } catch {
            return (success: false, stdout: "", errorMessage: error.localizedDescription)
        }
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL

        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("notch-exec-\(UUID().uuidString)", isDirectory: true)
        let stdoutURL = tempDirectoryURL.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectoryURL.appendingPathComponent("stderr.log")

        do {
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            fileManager.createFile(atPath: stdoutURL.path, contents: nil)
            fileManager.createFile(atPath: stderrURL.path, contents: nil)
        } catch {
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: "Couldn't prepare command output capture: \(error.localizedDescription)",
                timedOut: false
            )
        }

        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            try? fileManager.removeItem(at: tempDirectoryURL)
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: "Couldn't open command output capture: \(error.localizedDescription)",
                timedOut: false
            )
        }

        task.standardOutput = stdoutHandle
        task.standardError = stderrHandle

        do {
            try task.run()
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: tempDirectoryURL)
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: error.localizedDescription,
                timedOut: false
            )
        }

        let didTimeOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                task.waitUntilExit()
                return false
            }
            if let timeout {
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    if task.isRunning {
                        task.terminate()
                        return true
                    }
                    return false
                }
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        try? fileManager.removeItem(at: tempDirectoryURL)

        return ProcessResult(
            terminationStatus: task.terminationStatus,
            stdoutText: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderrText: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            runError: nil,
            timedOut: didTimeOut
        )
    }

    // MARK: - Calendar Tool

    func executeCalendar(action: String, args: [String: Any]) -> [String: Any] {
        let store = Self.calendarStore

        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            store.requestFullAccessToEvents { result, _ in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            guard granted else {
                return ["success": false, "error": "Calendar access was denied by the user."]
            }
        } else if status != .fullAccess {
            return ["success": false, "error": "Calendar access not granted. Enable in System Settings > Privacy & Security > Calendars."]
        }

        // Check reminders authorization if needed
        let isReminderAction = ["list_reminders", "create_reminder", "complete_reminder", "delete_reminder"].contains(action)
        if isReminderAction {
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            if reminderStatus == .notDetermined {
                let semaphore = DispatchSemaphore(value: 0)
                var granted = false
                store.requestFullAccessToReminders { result, _ in
                    granted = result
                    semaphore.signal()
                }
                semaphore.wait()
                guard granted else {
                    return ["success": false, "error": "Reminders access was denied by the user."]
                }
            } else if reminderStatus != .fullAccess {
                return ["success": false, "error": "Reminders access not granted. Enable in System Settings > Privacy & Security > Reminders."]
            }
        }

        switch action {
        case "list":
            return calendarList(store: store, args: args)
        case "create":
            return calendarCreate(store: store, args: args)
        case "delete":
            return calendarDelete(store: store, args: args)
        case "calendars":
            return calendarListCalendars(store: store)
        case "list_reminders":
            return reminderList(store: store, args: args)
        case "create_reminder":
            return reminderCreate(store: store, args: args)
        case "complete_reminder":
            return reminderComplete(store: store, args: args)
        case "delete_reminder":
            return reminderDelete(store: store, args: args)
        default:
            return ["success": false, "error": "Unknown action '\(action)'. Use: list, create, delete, calendars, list_reminders, create_reminder, complete_reminder, or delete_reminder."]
        }
    }

    private static let calendarDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let calendarDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, yyyy-MM-dd"
        return f
    }()

    // MARK: list

    private func calendarList(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        let cal = Calendar.current
        let now = Date()
        let daysBack = min(max((args["daysBack"] as? Int) ?? 0, 0), 30)
        let daysAhead = min(max((args["daysAhead"] as? Int) ?? 0, 0), 30)
        let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack, to: now)!)
        let endDate = cal.date(byAdding: .day, value: daysAhead + 1, to: cal.startOfDay(for: now))!

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        var events = store.events(matching: predicate)

        if let query, !query.isEmpty {
            events = events.filter { ($0.title ?? "").lowercased().contains(query) }
        }

        let df = Self.calendarDateFormatter
        let dayFmt = Self.calendarDayFormatter

        let eventEntries: [[String: Any]] = events.map { event in
            var entry: [String: Any] = [
                "id": event.eventIdentifier ?? "",
                "title": event.title ?? "(no title)",
                "start": df.string(from: event.startDate),
                "end": df.string(from: event.endDate),
                "allDay": event.isAllDay,
                "calendar": event.calendar.title,
            ]
            if let loc = event.location, !loc.isEmpty { entry["location"] = loc }
            if let notes = event.notes, !notes.isEmpty { entry["notes"] = String(notes.prefix(300)) }
            if event.hasRecurrenceRules { entry["recurring"] = true }
            return entry
        }

        let range: String
        if daysBack == 0 && daysAhead == 0 {
            range = "today (\(dayFmt.string(from: now)))"
        } else {
            range = "\(dayFmt.string(from: startDate)) → \(dayFmt.string(from: cal.date(byAdding: .day, value: -1, to: endDate)!))"
        }

        return [
            "success": true,
            "action": "list",
            "range": range,
            "eventCount": eventEntries.count,
            "events": eventEntries,
        ]
    }

    // MARK: create

    private func calendarCreate(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return ["success": false, "error": "Missing required field: title"]
        }

        let df = Self.calendarDateFormatter
        let isAllDay = (args["allDay"] as? Bool) ?? false

        let startDate: Date
        let endDate: Date

        if let startStr = args["startDate"] as? String, let parsed = df.date(from: startStr) {
            startDate = parsed
        } else if let startStr = args["startDate"] as? String {
            // Try date-only format for all-day events
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = dayOnly.date(from: startStr) {
                startDate = parsed
            } else {
                return ["success": false, "error": "Invalid startDate format. Use 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd'."]
            }
        } else {
            return ["success": false, "error": "Missing required field: startDate (format: 'yyyy-MM-dd HH:mm')"]
        }

        if let endStr = args["endDate"] as? String, let parsed = df.date(from: endStr) {
            endDate = parsed
        } else if let endStr = args["endDate"] as? String {
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = dayOnly.date(from: endStr) {
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: parsed)!
            } else {
                return ["success": false, "error": "Invalid endDate format. Use 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd'."]
            }
        } else if isAllDay {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        } else {
            endDate = startDate.addingTimeInterval(3600) // default 1 hour
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay

        if let location = args["location"] as? String, !location.isEmpty {
            event.location = location
        }
        if let notes = args["notes"] as? String, !notes.isEmpty {
            event.notes = notes
        }

        // Pick calendar
        if let calendarName = (args["calendarName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !calendarName.isEmpty {
            let match = store.calendars(for: .event).first {
                $0.title.lowercased() == calendarName.lowercased()
            }
            event.calendar = match ?? store.defaultCalendarForNewEvents
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        // Alert/notification
        let alertMinutes: Int?
        if let raw = args["alertMinutesBefore"] as? NSNumber {
            alertMinutes = raw.intValue
        } else if let raw = args["alertMinutesBefore"] as? Int {
            alertMinutes = raw
        } else {
            alertMinutes = nil
        }
        if let minutes = alertMinutes {
            let offset = -TimeInterval(max(minutes, 0) * 60)
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try store.save(event, span: .thisEvent)
            var eventInfo: [String: Any] = [
                "id": event.eventIdentifier ?? "",
                "title": event.title ?? "",
                "start": df.string(from: event.startDate),
                "end": df.string(from: event.endDate),
                "allDay": event.isAllDay,
                "calendar": event.calendar.title,
            ]
            if let minutes = alertMinutes {
                eventInfo["alert"] = minutes == 0 ? "at event time" : "\(minutes) min before"
            }
            return [
                "success": true,
                "action": "create",
                "message": "Event created successfully.",
                "event": eventInfo,
            ]
        } catch {
            return ["success": false, "error": "Failed to save event: \(error.localizedDescription)"]
        }
    }

    // MARK: delete

    private func calendarDelete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let eventId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !eventId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list' action first to get event IDs."]
        }

        guard let event = store.event(withIdentifier: eventId) else {
            return ["success": false, "error": "Event not found with ID: \(eventId)"]
        }

        let title = event.title ?? "(no title)"
        do {
            try store.remove(event, span: .thisEvent)
            return [
                "success": true,
                "action": "delete",
                "message": "Deleted event: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to delete event: \(error.localizedDescription)"]
        }
    }

    // MARK: calendars (list available)

    private func calendarListCalendars(store: EKEventStore) -> [String: Any] {
        let calendars = store.calendars(for: .event)
        let entries: [[String: Any]] = calendars.map { cal in
            [
                "name": cal.title,
                "type": cal.type == .calDAV ? "CalDAV" :
                        cal.type == .exchange ? "Exchange" :
                        cal.type == .local ? "Local" :
                        cal.type == .subscription ? "Subscription" :
                        cal.type == .birthday ? "Birthday" : "Other",
                "source": cal.source?.title ?? "Unknown",
                "allowsModify": cal.allowsContentModifications,
            ]
        }

        return [
            "success": true,
            "action": "calendars",
            "calendarCount": entries.count,
            "calendars": entries,
        ]
    }

    // MARK: - Reminders

    private func reminderList(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let showCompleted = (args["isCompleted"] as? Bool) ?? false
        let listName = (args["reminderList"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var targetCalendars: [EKCalendar]? = nil
        if let listName, !listName.isEmpty {
            let match = store.calendars(for: .reminder).filter {
                $0.title.lowercased() == listName.lowercased()
            }
            if !match.isEmpty { targetCalendars = match }
        }

        let predicate: NSPredicate
        if showCompleted {
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: Calendar.current.date(byAdding: .month, value: -3, to: Date()),
                ending: Date(),
                calendars: targetCalendars
            )
        } else {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: targetCalendars
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        var fetchedReminders: [EKReminder] = []
        store.fetchReminders(matching: predicate) { reminders in
            fetchedReminders = reminders ?? []
            semaphore.signal()
        }
        semaphore.wait()

        if let query, !query.isEmpty {
            fetchedReminders = fetchedReminders.filter {
                ($0.title ?? "").lowercased().contains(query)
            }
        }

        let df = Self.calendarDateFormatter
        let entries: [[String: Any]] = fetchedReminders.prefix(50).map { reminder in
            var entry: [String: Any] = [
                "id": reminder.calendarItemIdentifier,
                "title": reminder.title ?? "(no title)",
                "completed": reminder.isCompleted,
                "list": reminder.calendar.title,
            ]
            if let dueDate = reminder.dueDateComponents,
               let date = Calendar.current.date(from: dueDate) {
                entry["dueDate"] = df.string(from: date)
            }
            if let notes = reminder.notes, !notes.isEmpty {
                entry["notes"] = String(notes.prefix(200))
            }
            if let completionDate = reminder.completionDate {
                entry["completedDate"] = df.string(from: completionDate)
            }
            if reminder.priority > 0 {
                entry["priority"] = reminder.priority
            }
            return entry
        }

        return [
            "success": true,
            "action": "list_reminders",
            "filter": showCompleted ? "completed" : "pending",
            "reminderCount": entries.count,
            "reminders": entries,
        ]
    }

    private func reminderCreate(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return ["success": false, "error": "Missing required field: title"]
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title

        // Pick reminder list — defaultCalendarForNewReminders() can return nil on some setups.
        let allReminderCalendars = store.calendars(for: .reminder)
        let resolvedCalendar: EKCalendar?

        if let listName = (args["reminderList"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !listName.isEmpty {
            let match = allReminderCalendars.first {
                $0.title.lowercased() == listName.lowercased()
            }
            resolvedCalendar = match
                ?? store.defaultCalendarForNewReminders()
                ?? allReminderCalendars.first(where: { $0.allowsContentModifications })
        } else {
            resolvedCalendar = store.defaultCalendarForNewReminders()
                ?? allReminderCalendars.first(where: { $0.allowsContentModifications })
        }

        guard let targetCalendar = resolvedCalendar else {
            let available = allReminderCalendars.map { $0.title }.joined(separator: ", ")
            return ["success": false, "error": "No writable reminder list found. Available lists: \(available.isEmpty ? "none" : available). Open Reminders.app and create a list first."]
        }
        reminder.calendar = targetCalendar

        // Due date
        if let startStr = args["startDate"] as? String {
            let df = Self.calendarDateFormatter
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")

            if let parsed = df.date(from: startStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: parsed
                )
            } else if let parsed = dayOnly.date(from: startStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: parsed
                )
            }
        }

        if let notes = args["notes"] as? String, !notes.isEmpty {
            reminder.notes = notes
        }

        // Alert — for reminders, default to alerting at the due time (offset 0)
        let alertMinutes: Int
        if let raw = args["alertMinutesBefore"] as? NSNumber {
            alertMinutes = raw.intValue
        } else if let raw = args["alertMinutesBefore"] as? Int {
            alertMinutes = raw
        } else {
            alertMinutes = 0  // default: alert exactly at due time
        }
        if reminder.dueDateComponents != nil {
            let offset = -TimeInterval(max(alertMinutes, 0) * 60)
            reminder.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try store.save(reminder, commit: true)
            var info: [String: Any] = [
                "id": reminder.calendarItemIdentifier,
                "title": reminder.title ?? "",
                "list": reminder.calendar.title,
            ]
            if let dc = reminder.dueDateComponents,
               let date = Calendar.current.date(from: dc) {
                info["dueDate"] = Self.calendarDateFormatter.string(from: date)
            }
            info["alert"] = alertMinutes == 0 ? "at due time" : "\(alertMinutes) min before"
            return [
                "success": true,
                "action": "create_reminder",
                "message": "Reminder created successfully.",
                "reminder": info,
            ]
        } catch {
            return ["success": false, "error": "Failed to save reminder: \(error.localizedDescription)"]
        }
    }

    private func reminderComplete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let reminderId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reminderId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list_reminders' first."]
        }

        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return ["success": false, "error": "Reminder not found with ID: \(reminderId)"]
        }

        let title = item.title ?? "(no title)"
        item.isCompleted = true
        item.completionDate = Date()

        do {
            try store.save(item, commit: true)
            return [
                "success": true,
                "action": "complete_reminder",
                "message": "Completed reminder: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to complete reminder: \(error.localizedDescription)"]
        }
    }

    private func reminderDelete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let reminderId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reminderId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list_reminders' first."]
        }

        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return ["success": false, "error": "Reminder not found with ID: \(reminderId)"]
        }

        let title = item.title ?? "(no title)"
        do {
            try store.remove(item, commit: true)
            return [
                "success": true,
                "action": "delete_reminder",
                "message": "Deleted reminder: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to delete reminder: \(error.localizedDescription)"]
        }
    }


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

    private func truncatedToolOutput(_ value: String, limit: Int = 8000) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<endIndex]) + "\n...[truncated]"
    }
}

private struct ProcessResult {
    let terminationStatus: Int32?
    let stdoutText: String
    let stderrText: String
    let runError: String?
    let timedOut: Bool
}
