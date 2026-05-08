@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    private var workspaceCodingTools: GeminiWorkspaceCodingTools {
        GeminiWorkspaceCodingTools(
            workspaceRoot: GeminiLiveStoragePaths.workspaceRoot
        )
    }

    func executeReadFile(path: String, offset: Int? = nil, limit: Int? = nil) -> [String: Any] {
        workspaceCodingTools.executeReadFile(path: path, offset: offset, limit: limit)
    }

    nonisolated(unsafe) static let calendarStore = EKEventStore()

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
        GeminiLiveToolLogging.debug("tool response sent: \(toolResponseSummary(name: name, result: transportResult))")
    }

    private func toolResponseSummary(name: String, result: [String: Any]) -> String {
        var parts = ["name=\(name)"]
        if let success = result["success"] as? Bool {
            parts.append("success=\(success)")
        }
        if let action = result["action"] as? String {
            parts.append("action=\(action)")
        }
        if let exitCode = result["exitCode"] as? Int {
            parts.append("exitCode=\(exitCode)")
        }
        for key in ["count", "eventCount", "reminderCount", "calendarCount"] {
            if let value = result[key] {
                parts.append("\(key)=\(value)")
            }
        }
        if let stdoutTruncated = result["stdoutTruncated"] as? Bool {
            parts.append("stdoutTruncated=\(stdoutTruncated)")
        }
        if let stderrTruncated = result["stderrTruncated"] as? Bool {
            parts.append("stderrTruncated=\(stderrTruncated)")
        }
        return parts.joined(separator: " ")
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
    func executeExec(command: String, workingDirectory: String?, timeoutSeconds: Double?) async -> [String: Any] {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return ["success": false, "error": "Command is empty."]
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
        let outputMetadata: [String: Any] = [
            "stdoutTruncated": stdout.truncated,
            "stderrTruncated": stderr.truncated,
            "stdoutLength": process.stdoutText.count,
            "stderrLength": process.stderrText.count,
            "outputTruncationLimit": stdout.limit
        ]

        if let runError = process.runError {
            var result: [String: Any] = [
                "success": false,
                "state": "failed_to_start",
                "error": "Failed to start command: \(runError)"
            ]
            result.merge(outputMetadata) { current, _ in current }
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        if process.timedOut {
            var result: [String: Any] = [
                "success": false,
                "state": "timed_out",
                "error": "Command timed out after \(Int(timeout))s.",
                "exitCode": exitCode,
                "stdout": stdout.text,
                "stderr": stderr.text
            ]
            result.merge(outputMetadata) { current, _ in current }
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        var result: [String: Any] = [
            "success": exitCode == 0,
            "state": exitCode == 0 ? "completed" : "nonzero_exit",
            "message": exitCode == 0 ? "Command finished successfully." : "Command exited with status \(exitCode).",
            "exitCode": exitCode,
            "stdout": stdout.text,
            "stderr": stderr.text
        ]
        result.merge(outputMetadata) { current, _ in current }
        if let cwd {
            result["workingDirectory"] = cwd.path
        }
        return result
    }
}
