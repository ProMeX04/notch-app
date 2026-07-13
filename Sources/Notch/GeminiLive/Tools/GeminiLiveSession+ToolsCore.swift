@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    private var workspaceReadTool: GeminiWorkspaceReadTool {
        GeminiWorkspaceReadTool(
            workspaceRoot: GeminiLiveStoragePaths.workspaceRoot
        )
    }

    func executeReadFile(path: String, offset: Int? = nil, limit: Int? = nil) -> [String: Any] {
        workspaceReadTool.executeReadFile(path: path, offset: offset, limit: limit)
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
}
