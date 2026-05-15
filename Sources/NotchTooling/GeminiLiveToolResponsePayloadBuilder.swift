import Foundation

public enum GeminiLiveToolResponsePayloadBuilder {
    private static let supportedInlineDataMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/webp",
        "application/pdf",
        "text/plain",
    ]

    public static func buildToolResponsePayload(
        id: String,
        name: String,
        result: [String: Any]
    ) -> [String: Any] {
        let attachments = extractAttachments(from: result, toolName: name)
        let transportResult = sanitizedResult(from: result, attachments: attachments)

        var functionResponse: [String: Any] = [
            "id": id,
            "name": name,
            "response": [
                "result": transportResult,
            ],
        ]
        if !attachments.isEmpty {
            functionResponse["parts"] = attachments.map(\.partDictionary)
        }

        return [
            "toolResponse": [
                "functionResponses": [functionResponse],
            ],
        ]
    }

    public static func transportResult(
        from result: [String: Any],
        toolName: String
    ) -> [String: Any] {
        sanitizedResult(from: result, attachments: extractAttachments(from: result, toolName: toolName))
    }

    private static func extractAttachments(from result: [String: Any], toolName: String) -> [FunctionResponseAttachment] {
        guard let contentBlocks = result["contentBlocks"] as? [[String: Any]] else {
            return []
        }

        let basePath = (result["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var attachments: [FunctionResponseAttachment] = []

        for block in contentBlocks {
            guard let type = block["type"] as? String, type == "image" || type == "document" else { continue }
            guard let data = block["data"] as? String, !data.isEmpty else { continue }
            guard let mimeType = block["mimeType"] as? String, supportedInlineDataMimeTypes.contains(mimeType) else {
                continue
            }

            let displayName = attachmentDisplayName(
                explicit: block["displayName"] as? String,
                basePath: basePath,
                mimeType: mimeType,
                toolName: toolName,
                index: attachments.count
            )
            let kind: FunctionResponseAttachment.Kind = (type == "document") ? .document : .image
            attachments.append(
                FunctionResponseAttachment(
                    kind: kind,
                    displayName: displayName,
                    mimeType: mimeType,
                    data: data
                )
            )
        }

        return attachments
    }

    private static func attachmentDisplayName(
        explicit: String?,
        basePath: String?,
        mimeType: String,
        toolName: String,
        index: Int
    ) -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }

        let fallbackExtension = fileExtension(for: mimeType)
        if let basePath, !basePath.isEmpty {
            let lastPathComponent = URL(fileURLWithPath: basePath).lastPathComponent
            if !lastPathComponent.isEmpty, lastPathComponent != "." {
                if index == 0 {
                    return lastPathComponent
                }

                let stem = URL(fileURLWithPath: lastPathComponent).deletingPathExtension().lastPathComponent
                let ext = URL(fileURLWithPath: lastPathComponent).pathExtension
                let resolvedExtension = ext.isEmpty ? fallbackExtension : ext
                return "\(stem)-\(index + 1).\(resolvedExtension)"
            }
        }

        return "\(toolName)-attachment-\(index + 1).\(fallbackExtension)"
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/png":
            return "png"
        case "image/jpeg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "application/pdf":
            return "pdf"
        case "text/plain":
            return "txt"
        default:
            return "bin"
        }
    }

    private static func sanitizedResult(
        from result: [String: Any],
        attachments: [FunctionResponseAttachment]
    ) -> [String: Any] {
        var sanitized = result
        sanitized.removeValue(forKey: "contentBlocks")

        if var image = sanitized["image"] as? [String: Any] {
            image.removeValue(forKey: "data")
            sanitized["image"] = image
        }

        if attachments.count == 1, let attachment = attachments.first {
            sanitized["imageRef"] = ["$ref": attachment.displayName]
        } else if attachments.count > 1 {
            sanitized["mediaRefs"] = attachments.map { ["$ref": $0.displayName] }
        }

        return sanitized
    }
}

struct FunctionResponseAttachment {
    enum Kind {
        case image
        case document
    }

    let kind: Kind
    let displayName: String
    let mimeType: String
    let data: String

    var partDictionary: [String: Any] {
        [
            "inlineData": [
                "displayName": displayName,
                "mimeType": mimeType,
                "data": data,
            ],
        ]
    }
}
