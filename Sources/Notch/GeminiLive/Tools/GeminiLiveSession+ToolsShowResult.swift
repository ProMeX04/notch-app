import AppKit
import Foundation
import NotchTooling

extension GeminiLiveSession {
    /// Handles the `showResult` tool call. Parses items, validates file paths,
    /// and appends a single batch to the
    /// `AgentResultStore`. Auto-copies plain text only when the batch is a
    /// single short text item.
    func handleShowResultCall(id: String, call: [String: Any]) {
        let name = GeminiLiveToolName.showResult
        let rawArgs = call["args"] as? [String: Any] ?? [:]
        let args = GeminiToolArgumentNormalizer.normalize(rawArgs)
        let sendableArgs = SendableToolArgs(args: args)

        guard let rawItems = (args["items"] as? [[String: Any]]) ?? (args["items"] as? [Any])?.compactMap({ $0 as? [String: Any] }), !rawItems.isEmpty else {
            let result: [String: Any] = ["success": false, "error": "Missing or empty 'items' array."]
            notifyFunctionStarted(name: name, args: args)
            notifyFunctionExecuted(name: name, args: args, result: result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        notifyFunctionStarted(name: name, args: sendableArgs.args)

        let sendableItems = SendableToolArgs(args: ["items": rawItems])
        Task {
            let castItems = (sendableItems.args["items"] as? [[String: Any]]) ?? []
            let materialization = await AgentResultsToolMaterializer.materialize(rawItems: castItems)
            let resolvedItems = materialization.items
            let droppedReasons = materialization.droppedReasons

            if resolvedItems.isEmpty {
                let result: [String: Any] = [
                    "success": false,
                    "error": "No valid items.",
                    "droppedReasons": droppedReasons
                ]
                notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
                sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            await MainActor.run {
                AgentResultStore.shared.appendBatch(resolvedItems)
                AgentResultsToolMaterializer.autoCopyIfShortText(resolvedItems)
            }

            var result: [String: Any] = [
                "success": true,
                "count": resolvedItems.count
            ]
            if !droppedReasons.isEmpty {
                result["droppedReasons"] = droppedReasons
            }
            notifyFunctionExecuted(name: name, args: sendableArgs.args, result: result)
            sendFunctionResponse(id: id, name: name, result: result)
        }
    }
}

// MARK: - Materialization helpers

enum AgentResultsToolMaterializer {
    struct Outcome {
        let items: [AgentResultItem]
        let droppedReasons: [String]
    }

    private static let autoCopyMaxLength = 200

    static func materialize(rawItems: [[String: Any]]) async -> Outcome {
        let batchId = UUID()
        var resolved: [AgentResultItem] = []
        var droppedReasons: [String] = []

        for (index, raw) in rawItems.enumerated() {
            let kindRaw = (raw["kind"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (raw["title"] as? String).flatMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let content = raw["content"] as? String

            guard let kind = kindRaw, let content, !content.isEmpty else {
                droppedReasons.append("item[\(index)]: missing kind or content")
                continue
            }

            switch kind {
            case "text":
                resolved.append(AgentResultItem(
                    batchId: batchId,
                    title: title,
                    kind: .text(content),
                    isTemporaryAsset: false
                ))
            case "link":
                if let url = parseExternalURL(content) {
                    resolved.append(AgentResultItem(
                        batchId: batchId,
                        title: title,
                        kind: .link(url),
                        isTemporaryAsset: false
                    ))
                } else {
                    droppedReasons.append("item[\(index)]: invalid link URL")
                }
            case "file":
                if let item = materializeFile(content: content, batchId: batchId) {
                    resolved.append(item)
                } else {
                    droppedReasons.append("item[\(index)]: file path missing or unreadable")
                }
            default:
                droppedReasons.append("item[\(index)]: unknown kind '\(kind)'")
            }
        }

        return Outcome(items: resolved, droppedReasons: droppedReasons)
    }

    @MainActor
    static func autoCopyIfShortText(_ items: [AgentResultItem]) {
        guard items.count == 1, let item = items.first,
              case let .text(string) = item.kind,
              string.count <= autoCopyMaxLength else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Per-kind helpers

    private static func materializeFile(content: String, batchId: UUID) -> AgentResultItem? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = parseLocalPath(trimmed) else { return nil }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), fm.isReadableFile(atPath: url.path) else {
            return nil
        }
        return AgentResultItem(
            batchId: batchId,
            title: nil,
            kind: .file(url),
            isTemporaryAsset: false
        )
    }

    // MARK: - Parsing

    private static func parseExternalURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func parseLocalPath(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        return nil
    }

}
