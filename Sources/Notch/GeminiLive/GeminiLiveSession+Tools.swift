import Foundation
import NotchTooling

extension GeminiLiveSession {
    private var workspaceCodingTools: GeminiWorkspaceCodingTools {
        GeminiWorkspaceCodingTools(
            workspaceRoot: GeminiLiveStoragePaths.workspaceRoot,
            builtInSkillsDirectory: GeminiLiveStoragePaths.builtInSkillsDirectory
        )
    }

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
