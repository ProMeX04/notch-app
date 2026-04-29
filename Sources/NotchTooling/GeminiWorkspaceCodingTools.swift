import AppKit
import Quartz
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GeminiToolArgumentNormalizer {
    public static let pathKeys = ["path", "file_path", "filePath", "file"]

    public static func normalize(_ args: [String: Any]) -> [String: Any] {
        var normalized = args
        normalizeAliases(in: &normalized, canonical: "path", aliases: Array(pathKeys.dropFirst()))
        normalizeTextLikeValue(in: &normalized, key: "content")
        normalizeEditReplacements(in: &normalized)
        return normalized
    }

    public static func stringValue(
        in args: [String: Any],
        keys: [String],
        allowEmpty: Bool = false
    ) -> String? {
        let normalized = normalize(args)
        for key in keys {
            guard let value = normalized[key] else { continue }
            if let string = value as? String {
                if allowEmpty || !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return string
                }
            } else if let extracted = extractStructuredText(value), (allowEmpty || !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                return extracted
            }
        }
        return nil
    }

    public static func intValue(in args: [String: Any], keys: [String]) -> Int? {
        let normalized = normalize(args)
        for key in keys {
            guard let value = normalized[key] else { continue }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let int = value as? Int {
                return int
            }
            if let double = value as? Double, double.isFinite {
                return Int(double.rounded(.towardZero))
            }
            if let string = value as? String,
               let parsed = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }

    public static func boolValue(in args: [String: Any], keys: [String]) -> Bool? {
        let normalized = normalize(args)
        for key in keys {
            guard let value = normalized[key] else { continue }
            if let number = value as? NSNumber {
                return number.boolValue
            }
            if let bool = value as? Bool {
                return bool
            }
            if let string = value as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

    public static func editReplacements(in args: [String: Any]) -> [GeminiExactTextEdit] {
        let normalized = normalize(args)
        let replacements = normalized["edits"] as? [[String: String]] ?? []
        return replacements.compactMap { record in
            guard let oldText = record["oldText"], !oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            guard let newText = record["newText"] else { return nil }
            return GeminiExactTextEdit(oldText: oldText, newText: newText)
        }
    }

    private static func normalizeAliases(
        in args: inout [String: Any],
        canonical: String,
        aliases: [String]
    ) {
        if args[canonical] == nil {
            for alias in aliases {
                if let value = args[alias] {
                    args[canonical] = value
                    break
                }
            }
        }

        for alias in aliases {
            args.removeValue(forKey: alias)
        }
    }

    private static func normalizeTextLikeValue(in args: inout [String: Any], key: String) {
        guard let value = args[key] else { return }
        guard !(value is String), let extracted = extractStructuredText(value) else { return }
        args[key] = extracted
    }

    private static func normalizeEditReplacements(in args: inout [String: Any]) {
        var replacements: [[String: String]] = []

        if let edits = args["edits"] as? [Any] {
            for entry in edits {
                guard let normalized = normalizeEditReplacement(entry) else { continue }
                replacements.append([
                    "oldText": normalized.oldText,
                    "newText": normalized.newText,
                ])
            }
        }

        if !replacements.isEmpty {
            args["edits"] = replacements
        }
    }

    private static func normalizeEditReplacement(_ value: Any) -> GeminiExactTextEdit? {
        guard let record = value as? [String: Any] else { return nil }
        var normalized = record
        normalizeTextLikeValue(in: &normalized, key: "oldText")
        normalizeTextLikeValue(in: &normalized, key: "newText")

        guard let oldText = normalized["oldText"] as? String,
              !oldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let newText = normalized["newText"] as? String else {
            return nil
        }

        return GeminiExactTextEdit(oldText: oldText, newText: newText)
    }

    private static func extractStructuredText(_ value: Any, depth: Int = 0) -> String? {
        guard depth <= 6 else { return nil }

        if let string = value as? String {
            return string
        }

        if let array = value as? [Any] {
            let parts = array.compactMap { extractStructuredText($0, depth: depth + 1) }
            return parts.isEmpty ? nil : parts.joined()
        }

        guard let record = value as? [String: Any] else { return nil }

        if let text = record["text"] as? String {
            return text
        }

        if let content = record["content"] as? String {
            return content
        }

        if let contentParts = record["content"] as? [Any] {
            return extractStructuredText(contentParts, depth: depth + 1)
        }

        if let parts = record["parts"] as? [Any] {
            return extractStructuredText(parts, depth: depth + 1)
        }

        if let value = record["value"] as? String, !value.isEmpty {
            let type = (record["type"] as? String)?.lowercased() ?? ""
            let kind = (record["kind"] as? String)?.lowercased() ?? ""
            if type.contains("text") || kind == "text" {
                return value
            }
        }

        return nil
    }
}

public struct GeminiExactTextEdit: Equatable, Sendable {
    public let oldText: String
    public let newText: String

    public init(oldText: String, newText: String) {
        self.oldText = oldText
        self.newText = newText
    }
}

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

public struct GeminiWorkspaceCodingTools {
    public static let defaultReadMaxLines = 2_000
    public static let defaultReadMaxBytes = 50 * 1024
    public static let defaultAdaptiveReadBudgetBytes = 50 * 1024
    public static let defaultGrepMaxLineLength = 500
    public static let defaultInlineImageMaxBytes = Int(4.5 * 1024 * 1024)
    public static let defaultInlinePDFMaxBytes = 20 * 1024 * 1024
    public static let defaultInlineImageMaxDimension = 2_000
    public static let defaultJPEGQuality = 80
    private static let supportedGeminiInlineImageMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/webp",
    ]
    private static let supportedImageMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
    ]
    private static let unicodeSpaceVariants = [
        "\u{00A0}",
        "\u{2000}",
        "\u{2001}",
        "\u{2002}",
        "\u{2003}",
        "\u{2004}",
        "\u{2005}",
        "\u{2006}",
        "\u{2007}",
        "\u{2008}",
        "\u{2009}",
        "\u{200A}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]
    private static let narrowNoBreakSpace = "\u{202F}"

    public static let openClawReadToolDescription =
        "Read the contents of a file. Supports text files, images (jpg, png, gif, webp), and PDF documents. Images and PDFs are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
    public static let openClawReadPathParameterDescription =
        "Path to the file to read (relative or absolute)"
    public static let openClawReadOffsetParameterDescription =
        "Line number to start reading from (1-indexed)"
    public static let openClawReadLimitParameterDescription =
        "Maximum number of lines to read"
    public static let openClawWriteToolDescription =
        "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
    public static let openClawWritePathParameterDescription =
        "Path to the file to write (relative or absolute)"
    public static let openClawWriteContentParameterDescription =
        "Content to write to the file"
    public static let openClawLsToolDescription =
        "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first)."
    public static let openClawLsPathParameterDescription =
        "Directory to list (default: current directory)"
    public static let openClawLsLimitParameterDescription =
        "Maximum number of entries to return (default: 500)"
    public static let openClawEditToolDescription =
        "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes."
    public static let openClawEditPathParameterDescription =
        "Path to the file to edit (relative or absolute)"
    public static let openClawEditReplacementsParameterDescription =
        "One or more targeted replacements. Each edit is matched against the original file, not incrementally. Do not include overlapping or nested edits. If two changes touch the same block or nearby lines, merge them into one edit instead."
    public static let openClawEditOldTextParameterDescription =
        "Exact text for one targeted replacement. It must be unique in the original file and must not overlap with any other edits[].oldText in the same call."
    public static let openClawEditNewTextParameterDescription =
        "Replacement text for this targeted edit."
    public static let openClawFindToolDescription =
        "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first)."
    public static let openClawFindPatternParameterDescription =
        "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"
    public static let openClawFindPathParameterDescription =
        "Directory to search in (default: current directory)"
    public static let openClawFindLimitParameterDescription =
        "Maximum number of results (default: 1000)"
    public static let openClawGrepToolDescription =
        "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars."
    public static let openClawGrepPatternParameterDescription =
        "Search pattern (regex or literal string)"
    public static let openClawGrepPathParameterDescription =
        "Directory or file to search (default: current directory)"
    public static let openClawGrepGlobParameterDescription =
        "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"
    public static let openClawGrepIgnoreCaseParameterDescription =
        "Case-insensitive search (default: false)"
    public static let openClawGrepLiteralParameterDescription =
        "Treat pattern as literal string instead of regex (default: false)"
    public static let openClawGrepContextParameterDescription =
        "Number of lines to show before and after each match (default: 0)"
    public static let openClawGrepLimitParameterDescription =
        "Maximum number of matches to return (default: 100)"
    public static var openClawReadToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "path": [
                    "type": "STRING",
                    "description": openClawReadPathParameterDescription,
                ],
                "file_path": [
                    "type": "STRING",
                    "description": openClawReadPathParameterDescription,
                ],
                "filePath": [
                    "type": "STRING",
                    "description": openClawReadPathParameterDescription,
                ],
                "file": [
                    "type": "STRING",
                    "description": openClawReadPathParameterDescription,
                ],
                "offset": [
                    "type": "NUMBER",
                    "description": openClawReadOffsetParameterDescription,
                ],
                "limit": [
                    "type": "NUMBER",
                    "description": openClawReadLimitParameterDescription,
                ],
            ],
            "required": [],
        ]
    }
    public static var openClawWriteToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "path": [
                    "type": "STRING",
                    "description": openClawWritePathParameterDescription,
                ],
                "file_path": [
                    "type": "STRING",
                    "description": openClawWritePathParameterDescription,
                ],
                "filePath": [
                    "type": "STRING",
                    "description": openClawWritePathParameterDescription,
                ],
                "file": [
                    "type": "STRING",
                    "description": openClawWritePathParameterDescription,
                ],
                "content": [
                    "type": "STRING",
                    "description": openClawWriteContentParameterDescription,
                ],
            ],
            "required": ["content"],
        ]
    }
    public static var openClawLsToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "path": [
                    "type": "STRING",
                    "description": openClawLsPathParameterDescription,
                ],
                "limit": [
                    "type": "NUMBER",
                    "description": openClawLsLimitParameterDescription,
                ],
            ],
            "required": [],
        ]
    }
    public static var openClawEditToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "path": [
                    "type": "STRING",
                    "description": openClawEditPathParameterDescription,
                ],
                "file_path": [
                    "type": "STRING",
                    "description": openClawEditPathParameterDescription,
                ],
                "filePath": [
                    "type": "STRING",
                    "description": openClawEditPathParameterDescription,
                ],
                "file": [
                    "type": "STRING",
                    "description": openClawEditPathParameterDescription,
                ],
                "edits": [
                    "type": "ARRAY",
                    "description": openClawEditReplacementsParameterDescription,
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "oldText": [
                                "type": "STRING",
                                "description": openClawEditOldTextParameterDescription,
                            ],
                            "newText": [
                                "type": "STRING",
                                "description": openClawEditNewTextParameterDescription,
                            ],
                        ],
                        "required": ["oldText", "newText"],
                    ],
                ],
            ],
            "required": ["edits"],
        ]
    }
    public static var openClawFindToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "pattern": [
                    "type": "STRING",
                    "description": openClawFindPatternParameterDescription,
                ],
                "path": [
                    "type": "STRING",
                    "description": openClawFindPathParameterDescription,
                ],
                "limit": [
                    "type": "NUMBER",
                    "description": openClawFindLimitParameterDescription,
                ],
            ],
            "required": ["pattern"],
        ]
    }
    public static var openClawGrepToolParameters: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "pattern": [
                    "type": "STRING",
                    "description": openClawGrepPatternParameterDescription,
                ],
                "path": [
                    "type": "STRING",
                    "description": openClawGrepPathParameterDescription,
                ],
                "glob": [
                    "type": "STRING",
                    "description": openClawGrepGlobParameterDescription,
                ],
                "ignoreCase": [
                    "type": "BOOLEAN",
                    "description": openClawGrepIgnoreCaseParameterDescription,
                ],
                "literal": [
                    "type": "BOOLEAN",
                    "description": openClawGrepLiteralParameterDescription,
                ],
                "context": [
                    "type": "NUMBER",
                    "description": openClawGrepContextParameterDescription,
                ],
                "limit": [
                    "type": "NUMBER",
                    "description": openClawGrepLimitParameterDescription,
                ],
            ],
            "required": ["pattern"],
        ]
    }

    let workspaceRoot: URL
    let builtInSkillsDirectory: URL?
    let readMaxLines: Int
    let readMaxBytes: Int
    let adaptiveReadBudgetBytes: Int
    let grepMaxLineLength: Int
    let inlineImageMaxBytes: Int
    let inlineImageMaxDimension: Int
    let jpegQuality: Int
    let inlinePDFMaxBytes: Int
    let fileManager: FileManager

    public init(
        workspaceRoot: URL,
        builtInSkillsDirectory: URL?,
        readMaxLines: Int = defaultReadMaxLines,
        readMaxBytes: Int = defaultReadMaxBytes,
        adaptiveReadBudgetBytes: Int = defaultAdaptiveReadBudgetBytes,
        grepMaxLineLength: Int = defaultGrepMaxLineLength,
        inlineImageMaxBytes: Int = defaultInlineImageMaxBytes,
        inlineImageMaxDimension: Int = defaultInlineImageMaxDimension,
        jpegQuality: Int = defaultJPEGQuality,
        inlinePDFMaxBytes: Int = defaultInlinePDFMaxBytes,
        fileManager: FileManager = .default
    ) {
        self.workspaceRoot = workspaceRoot
        self.builtInSkillsDirectory = builtInSkillsDirectory
        self.readMaxLines = readMaxLines
        self.readMaxBytes = readMaxBytes
        self.adaptiveReadBudgetBytes = adaptiveReadBudgetBytes
        self.grepMaxLineLength = grepMaxLineLength
        self.inlineImageMaxBytes = inlineImageMaxBytes
        self.inlineImageMaxDimension = inlineImageMaxDimension
        self.jpegQuality = jpegQuality
        self.inlinePDFMaxBytes = inlinePDFMaxBytes
        self.fileManager = fileManager
    }

    public func resolvedWorkspacePath(from path: String?, directoryHint: Bool? = nil) -> URL? {
        let trimmed = normalizePathInput(path)
        guard !trimmed.isEmpty else { return nil }

        return resolveHostPathCandidate(
            trimmedPath: trimmed,
            baseDirectory: workspaceRoot,
            allowRelative: true,
            directoryHint: directoryHint,
            preferExistingReadVariant: false
        )
    }

    public func resolvedReadablePath(from path: String?, directoryHint: Bool? = nil) -> URL? {
        let trimmed = normalizePathInput(path)
        guard !trimmed.isEmpty else { return nil }

        return resolveHostPathCandidate(
            trimmedPath: trimmed,
            baseDirectory: workspaceRoot,
            allowRelative: true,
            directoryHint: directoryHint,
            preferExistingReadVariant: true
        )
    }

    public func workspaceRelativePath(for url: URL) -> String {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedWorkspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = resolvedWorkspaceRoot.path
        let filePath = resolvedURL.path
        guard filePath != workspacePath else { return "." }
        guard filePath.hasPrefix(workspacePath + "/") else { return filePath }
        return String(filePath.dropFirst(workspacePath.count + 1))
    }

    public func executeReadFile(path: String, offset: Int? = nil, limit: Int? = nil) -> [String: Any] {
        let normalizedOffset = max(offset ?? 1, 1)
        let normalizedLimit = limit.map { max($0, 1) }

        switch prepareReadableFile(path: path) {
        case .denied:
            return readPathErrorResult(path: path)
        case .error(let errorPayload):
            return errorPayload
        case .success(let file):
            if let imageMimeType = file.imageMimeType {
                return executeImageRead(file: file, mimeType: imageMimeType)
            }
            if let pdfMimeType = file.pdfMimeType {
                return executePDFRead(file: file, mimeType: pdfMimeType, offset: normalizedOffset, limit: normalizedLimit ?? Self.pdfMaxPages)
            }

            guard normalizedLimit == nil else {
                return executeExplicitRead(file: file, requestedPath: path, offset: normalizedOffset, limit: normalizedLimit)
            }

            let firstSlice = makeReadSlice(file: file, requestedPath: path, offset: normalizedOffset, limit: nil)
            if firstSlice.isErrorPayload {
                return firstSlice.payload
            }

            if firstSlice.firstLineExceedsLimit {
                return firstSlice.payload
            }

            var aggregatedText = ""
            var aggregatedBytes = 0
            var currentSlice = firstSlice
            var continuationOffset: Int?

            for _ in 0..<8 {
                let pageText = currentSlice.primaryText
                let nextChunk = aggregatedText.isEmpty ? pageText : "\n\n" + pageText
                let nextBytes = byteCount(of: nextChunk)

                if !aggregatedText.isEmpty && aggregatedBytes + nextBytes > adaptiveReadBudgetBytes {
                    continuationOffset = currentSlice.offset
                    break
                }

                aggregatedText += nextChunk
                aggregatedBytes += nextBytes

                guard let nextOffset = currentSlice.continuationOffset else {
                    return currentSlice.materializePayload(overridingContent: aggregatedText, overridingContinuationOffset: nil, capped: false)
                }

                continuationOffset = nextOffset

                if aggregatedBytes >= adaptiveReadBudgetBytes {
                    break
                }

                let nextSlice = makeReadSlice(file: file, requestedPath: path, offset: nextOffset, limit: nil)
                if nextSlice.isErrorPayload {
                    break
                }

                currentSlice = nextSlice
            }

            if let continuationOffset {
                let cappedNotice = "[Read output capped at \(formatRoundedBytes(adaptiveReadBudgetBytes)) for this call. Use offset=\(continuationOffset) to continue.]"
                let content = aggregatedText.isEmpty ? cappedNotice : aggregatedText + "\n\n" + cappedNotice
                return firstSlice.materializePayload(
                    overridingContent: content,
                    overridingContinuationOffset: continuationOffset,
                    capped: true
                )
            }

            return firstSlice.payload
        }
    }

    public func executeWriteFile(path: String, content: String) -> [String: Any] {
        guard let fileURL = resolvedWorkspacePath(from: path) else {
            return workspacePathErrorResult(path: path)
        }

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            let reportedBytes = openClawReportedWriteSize(of: content)
            return [
                "success": true,
                "path": workspaceRelativePath(for: fileURL),
                "absolutePath": fileURL.path,
                "bytes": reportedBytes,
                "message": "Successfully wrote \(reportedBytes) bytes to \(path)"
            ]
        } catch {
            return ["success": false, "error": "Couldn't write file: \(error.localizedDescription)"]
        }
    }

    public func executeEditFile(path: String, edits: [GeminiExactTextEdit]) -> [String: Any] {
        guard let fileURL = resolvedWorkspacePath(from: path) else {
            return workspacePathErrorResult(path: path)
        }

        guard !edits.isEmpty else {
            return ["success": false, "error": "Edit tool input is invalid. edits must contain at least one replacement."]
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "File does not exist: \(path)"]
        }
        guard !isDirectory.boolValue else {
            return ["success": false, "error": "Path is a directory, not a file: \(path)"]
        }

        do {
            let rawData = try Data(contentsOf: fileURL)
            let rawContent = String(decoding: rawData, as: UTF8.self)
            let stripped = stripUTF8Bom(from: rawContent)
            let originalEnding = detectLineEnding(in: stripped.text)
            let normalizedContent = normalizeToLF(stripped.text)
            let applied = try applyEditsToNormalizedContent(normalizedContent, edits: edits, path: path)
            let finalContent = stripped.bom + restoreLineEndings(applied.newContent, lineEnding: originalEnding)

            try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let diff = generateEditDiffString(oldContent: applied.baseContent, newContent: applied.newContent)

            return [
                "success": true,
                "path": workspaceRelativePath(for: fileURL),
                "absolutePath": fileURL.path,
                "replacements": edits.count,
                "message": "Successfully replaced \(edits.count) block(s) in \(path).",
                "diff": diff.diff,
                "firstChangedLine": diff.firstChangedLine as Any? ?? NSNull(),
                "details": [
                    "diff": diff.diff,
                    "firstChangedLine": diff.firstChangedLine as Any? ?? NSNull(),
                ],
            ]
        } catch {
            let currentContent = try? String(contentsOf: fileURL, encoding: .utf8)
            return ["success": false, "error": enhancedEditErrorMessage(for: error, currentContent: currentContent)]
        }
    }

    public func executeFind(pattern: String, path: String? = nil, limit: Int? = nil) -> [String: Any] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return ["success": false, "error": "Pattern is empty."]
        }

        let searchRoot: URL
        if let path, !normalizePathInput(path).isEmpty {
            guard let resolved = resolvedWorkspacePath(from: path, directoryHint: true) else {
                return workspacePathErrorResult(path: path)
            }
            searchRoot = resolved
        } else {
            searchRoot = workspaceRoot
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: searchRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ["success": false, "error": "Path not found: \(searchRoot.path)"]
        }

        let effectiveLimit = max(limit ?? 1000, 1)
        let searchResult: (matches: [String], error: String?)
        if let fdPath = locateFindExecutable() {
            searchResult = runFindWithFD(
                executablePath: fdPath,
                pattern: trimmedPattern,
                searchRoot: searchRoot,
                limit: effectiveLimit
            )
        } else {
            searchResult = (fallbackFindMatches(pattern: trimmedPattern, searchRoot: searchRoot, limit: effectiveLimit), nil)
        }

        if let error = searchResult.error {
            return ["success": false, "error": error]
        }

        let sortedMatches = searchResult.matches.sorted()
        let matches = Array(sortedMatches.prefix(effectiveLimit))
        let searchPath = workspaceRelativePath(for: searchRoot)
        guard !matches.isEmpty else {
            return [
                "success": true,
                "pattern": trimmedPattern,
                "path": searchPath,
                "output": "No files found matching pattern",
                "matches": [],
                "count": 0,
                "limit": effectiveLimit,
            ]
        }

        let rawOutput = matches.joined(separator: "\n")
        let truncation = truncateHead(rawOutput, maxLines: .max, maxBytes: readMaxBytes)
        var output = truncation.content
        var notices: [String] = []
        let resultLimitReached = sortedMatches.count >= effectiveLimit ? effectiveLimit : nil

        if let resultLimitReached {
            notices.append("\(resultLimitReached) results limit reached. Use limit=\(resultLimitReached * 2) for more, or refine pattern")
        }
        if truncation.truncated {
            notices.append("\(formatOpenClawSize(readMaxBytes)) limit reached")
        }
        if !notices.isEmpty {
            output += "\n\n[\(notices.joined(separator: ". "))]"
        }

        return [
            "success": true,
            "pattern": trimmedPattern,
            "path": searchPath,
            "output": output,
            "matches": matches,
            "count": matches.count,
            "limit": effectiveLimit,
            "resultLimitReached": resultLimitReached as Any? ?? NSNull(),
            "truncation": truncation.truncated ? truncation.dictionary : NSNull(),
        ]
    }

    public func executeLs(path: String? = nil, limit: Int? = nil) -> [String: Any] {
        let targetURL: URL
        if let path, !normalizePathInput(path).isEmpty {
            guard let resolved = resolvedWorkspacePath(from: path, directoryHint: true) else {
                return workspacePathErrorResult(path: path)
            }
            targetURL = resolved
        } else {
            targetURL = workspaceRoot
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "Path not found: \(targetURL.path)"]
        }
        guard isDirectory.boolValue else {
            return ["success": false, "error": "Not a directory: \(targetURL.path)"]
        }

        let effectiveLimit = max(limit ?? 500, 1)

        do {
            let childURLs = try fileManager.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            let sortedEntries = try childURLs
                .map { url -> String in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                    return url.lastPathComponent + (values.isDirectory == true ? "/" : "")
                }
                .sorted { lhs, rhs in
                    let lhsLower = lhs.lowercased()
                    let rhsLower = rhs.lowercased()
                    if lhsLower == rhsLower {
                        return lhs < rhs
                    }
                    return lhsLower < rhsLower
                }

            guard !sortedEntries.isEmpty else {
                return [
                    "success": true,
                    "path": workspaceRelativePath(for: targetURL),
                    "output": "(empty directory)",
                    "entries": [],
                    "count": 0,
                    "limit": effectiveLimit,
                ]
            }

            let entries = Array(sortedEntries.prefix(effectiveLimit))
            let rawOutput = entries.joined(separator: "\n")
            let truncation = truncateHead(rawOutput, maxLines: .max, maxBytes: readMaxBytes)
            var output = truncation.content
            var notices: [String] = []
            let entryLimitReached = sortedEntries.count >= effectiveLimit ? effectiveLimit : nil

            if let entryLimitReached {
                notices.append("\(entryLimitReached) entries limit reached. Use limit=\(entryLimitReached * 2) for more")
            }
            if truncation.truncated {
                notices.append("\(formatOpenClawSize(readMaxBytes)) limit reached")
            }
            if !notices.isEmpty {
                output += "\n\n[\(notices.joined(separator: ". "))]"
            }

            return [
                "success": true,
                "path": workspaceRelativePath(for: targetURL),
                "output": output,
                "entries": entries,
                "count": entries.count,
                "limit": effectiveLimit,
                "entryLimitReached": entryLimitReached as Any? ?? NSNull(),
                "truncation": truncation.truncated ? truncation.dictionary : NSNull(),
            ]
        } catch {
            return ["success": false, "error": "Cannot read directory: \(error.localizedDescription)"]
        }
    }

    public func executeGrep(
        pattern: String,
        path: String?,
        glob: String? = nil,
        ignoreCase: Bool = false,
        literal: Bool = false,
        context: Int = 0,
        limit: Int = 100
    ) -> [String: Any] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return ["success": false, "error": "Pattern is empty."]
        }

        let targetURL: URL
        if let path, !normalizePathInput(path).isEmpty {
            guard let resolved = resolvedWorkspacePath(from: path) else {
                return workspacePathErrorResult(path: path)
            }
            targetURL = resolved
        } else {
            targetURL = workspaceRoot
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "Path does not exist: \(path ?? ".")"]
        }

        guard let rgPath = locateExecutable(named: "rg") else {
            return ["success": false, "error": "ripgrep (rg) is not available."]
        }

        let effectiveContext = max(context, 0)
        let effectiveLimit = max(limit, 1)
        var arguments = ["--json", "--line-number", "--color=never", "--hidden"]
        if ignoreCase {
            arguments.append("--ignore-case")
        }
        if literal {
            arguments.append("--fixed-strings")
        }
        if let glob, !glob.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--glob", glob])
        }
        arguments.append(contentsOf: [trimmedPattern, targetURL.path])

        let process = runCommand(executablePath: rgPath, arguments: arguments, timeout: 15)
        if let runError = process.runError {
            return ["success": false, "error": "Failed to run ripgrep: \(runError)"]
        }
        if process.timedOut {
            return ["success": false, "error": "ripgrep timed out."]
        }
        if process.exitCode != 0 && process.exitCode != 1 {
            let stderr = process.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["success": false, "error": stderr.isEmpty ? "ripgrep exited with code \(process.exitCode)." : stderr]
        }

        let matches = collectRipgrepMatches(from: process.stdout, limit: effectiveLimit)
        if matches.items.isEmpty {
            return [
                "success": true,
                "pattern": trimmedPattern,
                "path": workspaceRelativePath(for: targetURL),
                "output": "No matches found",
                "matches": [],
                "count": 0,
                "limit": effectiveLimit,
                "context": effectiveContext
            ]
        }

        let formatted = formatGrepOutput(
            matches: matches.items,
            searchRoot: targetURL,
            searchPathIsDirectory: isDirectory.boolValue,
            context: effectiveContext
        )
        let truncation = truncateHead(formatted.output, maxLines: .max, maxBytes: readMaxBytes)
        var output = truncation.content
        var notices: [String] = []

        if matches.limitReached {
            notices.append("\(effectiveLimit) matches limit reached. Use limit=\(effectiveLimit * 2) for more, or refine pattern")
        }
        if truncation.truncated {
            notices.append("\(formatRoundedBytes(readMaxBytes)) limit reached")
        }
        if formatted.linesTruncated {
            notices.append("Some lines truncated to \(grepMaxLineLength) chars. Use read tool to see full lines")
        }
        if !notices.isEmpty {
            output += "\n\n[\(notices.joined(separator: ". "))]"
        }

        return [
            "success": true,
            "pattern": trimmedPattern,
            "path": workspaceRelativePath(for: targetURL),
            "output": output,
            "matches": formatted.matches,
            "count": matches.items.count,
            "limit": effectiveLimit,
            "context": effectiveContext,
            "matchLimitReached": matches.limitReached ? effectiveLimit : NSNull(),
            "linesTruncated": formatted.linesTruncated,
            "truncation": truncation.truncated ? truncation.dictionary : NSNull()
        ]
    }

    public func workspacePathErrorResult(path: String) -> [String: Any] {
        [
            "success": false,
            "error": "Invalid path: \(path)"
        ]
    }

    public func readPathErrorResult(path: String) -> [String: Any] {
        [
            "success": false,
            "error": "Invalid read path: \(path)"
        ]
    }

    private func executeExplicitRead(
        file: ReadableFile,
        requestedPath: String,
        offset: Int,
        limit: Int?
    ) -> [String: Any] {
        makeReadSlice(file: file, requestedPath: requestedPath, offset: offset, limit: limit).payload
    }

    private func makeReadSlice(file: ReadableFile, requestedPath: String, offset: Int, limit: Int?) -> ReadSlice {
        do {
            let data = try Data(contentsOf: file.url)
            let textContent = String(decoding: data, as: UTF8.self)
            let allLines = textContent.components(separatedBy: "\n")
            let totalLines = allLines.count
            let normalizedOffset = max(offset, 1)
            let startIndex = normalizedOffset - 1
            guard startIndex < totalLines else {
                return ReadSlice.error(["success": false, "error": "Offset \(normalizedOffset) is beyond end of file (\(totalLines) lines total)"])
            }

            let selectedContent: String
            let userLimitedLines: Int?
            if let limit {
                let endIndex = min(startIndex + max(limit, 1), totalLines)
                selectedContent = allLines[startIndex..<endIndex].joined(separator: "\n")
                userLimitedLines = endIndex - startIndex
            } else {
                selectedContent = allLines[startIndex...].joined(separator: "\n")
                userLimitedLines = nil
            }

            let truncation = truncateHead(selectedContent, maxLines: readMaxLines, maxBytes: readMaxBytes)
            let startLine = startIndex + 1
            let endLine = truncation.outputLines > 0 ? startLine + truncation.outputLines - 1 : startLine

            let primaryText: String
            let noticeText: String?
            let continuationOffset: Int?

            if truncation.firstLineExceedsLimit {
                let lineBytes = byteCount(of: allLines[startIndex])
                primaryText = "[Line \(startLine) is \(formatRoundedBytes(lineBytes)), exceeds \(formatRoundedBytes(readMaxBytes)) limit. Use bash: sed -n '\(startLine)p' \(requestedPath) | head -c \(readMaxBytes)]"
                noticeText = nil
                continuationOffset = nil
            } else if truncation.truncated {
                let nextOffset = endLine + 1
                let notice: String
                if truncation.truncatedBy == "lines" {
                    notice = "[Showing lines \(startLine)-\(endLine) of \(totalLines). Use offset=\(nextOffset) to continue.]"
                } else {
                    notice = "[Showing lines \(startLine)-\(endLine) of \(totalLines) (\(formatRoundedBytes(readMaxBytes)) limit). Use offset=\(nextOffset) to continue.]"
                }
                primaryText = truncation.content
                noticeText = notice
                continuationOffset = nextOffset
            } else if let userLimitedLines, startIndex + userLimitedLines < totalLines {
                let remaining = totalLines - (startIndex + userLimitedLines)
                let nextOffset = startIndex + userLimitedLines + 1
                primaryText = truncation.content
                noticeText = "[\(remaining) more lines in file. Use offset=\(nextOffset) to continue.]"
                continuationOffset = nextOffset
            } else {
                primaryText = truncation.content
                noticeText = nil
                continuationOffset = nil
            }

            return ReadSlice(
                url: file.url,
                relativePath: file.relativePath,
                encoding: "utf-8",
                offset: normalizedOffset,
                limit: limit,
                totalLines: totalLines,
                lineStart: startLine,
                lineEnd: endLine,
                primaryText: primaryText,
                noticeText: noticeText,
                continuationOffset: continuationOffset,
                truncation: truncation.truncated ? truncation : nil,
                firstLineExceedsLimit: truncation.firstLineExceedsLimit
            )
        } catch {
            return ReadSlice.error(["success": false, "error": "Couldn't read file: \(error.localizedDescription)"])
        }
    }

    private func executeImageRead(file: ReadableFile, mimeType: String) -> [String: Any] {
        do {
            let data = try Data(contentsOf: file.url)
            let prepared = prepareInlineImagePayload(data: data, mimeType: mimeType)
            let text: String
            var result: [String: Any] = [
                "success": true,
                "path": file.relativePath,
                "absolutePath": file.url.path,
                "mimeType": mimeType,
            ]

            if let prepared {
                text = imageReadText(mimeType: prepared.mimeType, metadata: prepared)
                result["content"] = text
                result["contentBlocks"] = [
                    [
                        "type": "text",
                        "text": text,
                    ],
                    prepared.contentBlock,
                ]
                result["image"] = prepared.dictionary
                result["mimeType"] = prepared.mimeType
            } else {
                text = "Read image file [\(mimeType)]\n[Image omitted: could not be resized below the inline image size limit.]"
                result["content"] = text
                result["contentBlocks"] = [
                    [
                        "type": "text",
                        "text": text,
                    ],
                ]
                result["imageOmitted"] = true
            }

            return result
        } catch {
            return ["success": false, "error": "Couldn't read file: \(error.localizedDescription)"]
        }
    }

    private static let pdfMaxPages = 10

    private func executePDFRead(file: ReadableFile, mimeType: String, offset: Int, limit: Int) -> [String: Any] {
        guard let pdfDoc = PDFDocument(url: file.url) else {
            return ["success": false, "error": "Couldn't open PDF: \(file.relativePath)"]
        }

        let totalPages = pdfDoc.pageCount
        let startPage = max(offset, 1)
        guard startPage <= totalPages else {
            return [
                "success": true,
                "path": file.relativePath,
                "absolutePath": file.url.path,
                "mimeType": mimeType,
                "content": "No more pages. PDF has \(totalPages) page\(totalPages == 1 ? "" : "s") total.",
                "totalPages": totalPages,
            ]
        }

        let endPage = min(startPage + limit - 1, totalPages)
        let hasMore = endPage < totalPages

        var extractedText = ""
        for pageIndex in startPage...endPage {
            guard let page = pdfDoc.page(at: pageIndex - 1) else { continue }
            let pageText = page.string ?? ""
            extractedText += "--- Page \(pageIndex) ---\n\(pageText)\n\n"
        }

        var header = "Read PDF [\(mimeType)] — pages \(startPage)-\(endPage) of \(totalPages)\n"
        if hasMore {
            header += "[Use offset=\(endPage + 1) to continue reading remaining \(totalPages - endPage) pages]\n"
        }
        let content = header + "\n" + extractedText
        let truncation = truncateHead(content, maxLines: readMaxLines, maxBytes: readMaxBytes)

        var result: [String: Any] = [
            "success": true,
            "path": file.relativePath,
            "absolutePath": file.url.path,
            "mimeType": mimeType,
            "content": truncation.content,
            "totalPages": totalPages,
            "startPage": startPage,
            "endPage": endPage,
        ]
        if hasMore {
            result["continuationOffset"] = endPage + 1
        }
        return result
    }

    private func applyEditsToNormalizedContent(
        _ normalizedContent: String,
        edits: [GeminiExactTextEdit],
        path: String
    ) throws -> AppliedEditContent {
        let normalizedEdits = edits.map {
            GeminiExactTextEdit(oldText: normalizeToLF($0.oldText), newText: normalizeToLF($0.newText))
        }

        for (index, edit) in normalizedEdits.enumerated() where edit.oldText.isEmpty {
            throw editEmptyOldTextError(path: path, editIndex: index, totalEdits: normalizedEdits.count)
        }

        let initialMatches = normalizedEdits.map { fuzzyFindText(in: normalizedContent, needle: $0.oldText) }
        let baseContent = initialMatches.contains(where: \.usedFuzzyMatch)
            ? normalizeForFuzzyMatch(normalizedContent)
            : normalizedContent

        var matchedEdits: [MatchedEdit] = []
        for (index, edit) in normalizedEdits.enumerated() {
            let match = fuzzyFindText(in: baseContent, needle: edit.oldText)
            guard match.found else {
                throw editNotFoundError(path: path, editIndex: index, totalEdits: normalizedEdits.count)
            }

            let occurrences = fuzzyOccurrenceCount(in: baseContent, needle: edit.oldText)
            if occurrences > 1 {
                throw editDuplicateError(
                    path: path,
                    editIndex: index,
                    totalEdits: normalizedEdits.count,
                    occurrences: occurrences
                )
            }

            matchedEdits.append(
                MatchedEdit(
                    editIndex: index,
                    matchIndex: match.index,
                    matchLength: match.matchLength,
                    newText: edit.newText
                )
            )
        }

        matchedEdits.sort { $0.matchIndex < $1.matchIndex }
        for index in 1..<matchedEdits.count {
            let previous = matchedEdits[index - 1]
            let current = matchedEdits[index]
            if previous.matchIndex + previous.matchLength > current.matchIndex {
                throw NSError(
                    domain: "GeminiWorkspaceCodingTools",
                    code: 0,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "edits[\(previous.editIndex)] and edits[\(current.editIndex)] overlap in \(path). Merge them into one edit or target disjoint regions."
                    ]
                )
            }
        }

        let baseNSString = baseContent as NSString
        var updated = baseContent
        for match in matchedEdits.reversed() {
            let updatedNSString = updated as NSString
            updated =
                updatedNSString.substring(to: match.matchIndex) +
                match.newText +
                updatedNSString.substring(from: match.matchIndex + match.matchLength)
        }

        if baseNSString.isEqual(to: updated) {
            throw editNoChangeError(path: path, totalEdits: normalizedEdits.count)
        }

        return AppliedEditContent(baseContent: baseContent, newContent: updated)
    }

    private func detectLineEnding(in content: String) -> String {
        let crlfRange = (content as NSString).range(of: "\r\n")
        let lfRange = (content as NSString).range(of: "\n")
        if lfRange.location == NSNotFound {
            return "\n"
        }
        if crlfRange.location == NSNotFound {
            return "\n"
        }
        return crlfRange.location < lfRange.location ? "\r\n" : "\n"
    }

    private func normalizeToLF(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func restoreLineEndings(_ text: String, lineEnding: String) -> String {
        guard lineEnding == "\r\n" else { return text }
        return text.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private func stripUTF8Bom(from content: String) -> (bom: String, text: String) {
        content.hasPrefix("\u{FEFF}") ? ("\u{FEFF}", String(content.dropFirst())) : ("", content)
    }

    private func normalizeForFuzzyMatch(_ text: String) -> String {
        let compatibilityNormalized = text.precomposedStringWithCompatibilityMapping
        let trimmedLines = compatibilityNormalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.reversed().drop(while: \.isWhitespace).reversed()
            }
            .map(String.init)
            .joined(separator: "\n")

        return trimmedLines
            .replacingOccurrences(of: "[\\u2018\\u2019\\u201A\\u201B]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[\\u201C\\u201D\\u201E\\u201F]", with: "\"", options: .regularExpression)
            .replacingOccurrences(of: "[\\u2010\\u2011\\u2012\\u2013\\u2014\\u2015\\u2212]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[\\u00A0\\u2002-\\u200A\\u202F\\u205F\\u3000]", with: " ", options: .regularExpression)
    }

    private func fuzzyFindText(in content: String, needle: String) -> FuzzyEditMatch {
        let exactRange = (content as NSString).range(of: needle)
        if exactRange.location != NSNotFound {
            return FuzzyEditMatch(
                found: true,
                index: exactRange.location,
                matchLength: exactRange.length,
                usedFuzzyMatch: false
            )
        }

        let fuzzyContent = normalizeForFuzzyMatch(content)
        let fuzzyNeedle = normalizeForFuzzyMatch(needle)
        let fuzzyRange = (fuzzyContent as NSString).range(of: fuzzyNeedle)
        guard fuzzyRange.location != NSNotFound else {
            return FuzzyEditMatch(found: false, index: -1, matchLength: 0, usedFuzzyMatch: false)
        }

        return FuzzyEditMatch(
            found: true,
            index: fuzzyRange.location,
            matchLength: fuzzyRange.length,
            usedFuzzyMatch: true
        )
    }

    private func fuzzyOccurrenceCount(in content: String, needle: String) -> Int {
        let normalizedContent = normalizeForFuzzyMatch(content)
        let normalizedNeedle = normalizeForFuzzyMatch(needle)
        guard !normalizedNeedle.isEmpty else { return 0 }
        return normalizedContent.components(separatedBy: normalizedNeedle).count - 1
    }

    private func editNotFoundError(path: String, editIndex: Int, totalEdits: Int) -> NSError {
        let message: String
        if totalEdits == 1 {
            message = "Could not find the exact text in \(path). The old text must match exactly including all whitespace and newlines."
        } else {
            message = "Could not find edits[\(editIndex)] in \(path). The oldText must match exactly including all whitespace and newlines."
        }
        return NSError(domain: "GeminiWorkspaceCodingTools", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func editDuplicateError(path: String, editIndex: Int, totalEdits: Int, occurrences: Int) -> NSError {
        let message: String
        if totalEdits == 1 {
            message = "Found \(occurrences) occurrences of the text in \(path). The text must be unique. Please provide more context to make it unique."
        } else {
            message = "Found \(occurrences) occurrences of edits[\(editIndex)] in \(path). Each oldText must be unique. Please provide more context to make it unique."
        }
        return NSError(domain: "GeminiWorkspaceCodingTools", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func editEmptyOldTextError(path: String, editIndex: Int, totalEdits: Int) -> NSError {
        let message: String
        if totalEdits == 1 {
            message = "oldText must not be empty in \(path)."
        } else {
            message = "edits[\(editIndex)].oldText must not be empty in \(path)."
        }
        return NSError(domain: "GeminiWorkspaceCodingTools", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func editNoChangeError(path: String, totalEdits: Int) -> NSError {
        let message: String
        if totalEdits == 1 {
            message = "No changes made to \(path). The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
        } else {
            message = "No changes made to \(path). The replacements produced identical content."
        }
        return NSError(domain: "GeminiWorkspaceCodingTools", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func enhancedEditErrorMessage(for error: Error, currentContent: String?) -> String {
        let message = error.localizedDescription
        guard message.contains("Could not find the exact text in") || message.contains("Could not find edits[") else {
            return message
        }
        guard let currentContent else { return message }

        let limit = 800
        let snippet: String
        if currentContent.count <= limit {
            snippet = currentContent
        } else {
            let endIndex = currentContent.index(currentContent.startIndex, offsetBy: limit)
            snippet = String(currentContent[..<endIndex]) + "\n... (truncated)"
        }
        return message + "\nCurrent file contents:\n" + snippet
    }

    private func generateEditDiffString(
        oldContent: String,
        newContent: String,
        contextLines: Int = 4
    ) -> EditDiffResult {
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")
        let sharedPrefixCount = zip(oldLines, newLines).prefix { $0 == $1 }.count

        if sharedPrefixCount == oldLines.count && sharedPrefixCount == newLines.count {
            return EditDiffResult(diff: "", firstChangedLine: nil)
        }

        var oldSuffixIndex = oldLines.count - 1
        var newSuffixIndex = newLines.count - 1
        while oldSuffixIndex >= sharedPrefixCount,
              newSuffixIndex >= sharedPrefixCount,
              oldLines[oldSuffixIndex] == newLines[newSuffixIndex] {
            oldSuffixIndex -= 1
            newSuffixIndex -= 1
        }

        let firstChangedLine = sharedPrefixCount + 1
        let lineNumberWidth = String(max(oldLines.count, newLines.count, 1)).count
        var output: [String] = []

        let leadingContextStart = max(0, sharedPrefixCount - contextLines)
        if leadingContextStart < sharedPrefixCount {
            for lineIndex in leadingContextStart..<sharedPrefixCount {
                output.append(" \(String(lineIndex + 1).padLeft(to: lineNumberWidth)) \(oldLines[lineIndex])")
            }
        }

        if sharedPrefixCount > leadingContextStart {
            output.append(" \(String(repeating: " ", count: lineNumberWidth)) ...")
        }

        if sharedPrefixCount <= oldSuffixIndex {
            for lineIndex in sharedPrefixCount...oldSuffixIndex {
                output.append("-\(String(lineIndex + 1).padLeft(to: lineNumberWidth)) \(oldLines[lineIndex])")
            }
        }
        if sharedPrefixCount <= newSuffixIndex {
            for lineIndex in sharedPrefixCount...newSuffixIndex {
                output.append("+\(String(lineIndex + 1).padLeft(to: lineNumberWidth)) \(newLines[lineIndex])")
            }
        }

        let trailingContextEnd = min(newLines.count, newSuffixIndex + contextLines + 1)
        if newSuffixIndex + 1 < trailingContextEnd {
            output.append(" \(String(repeating: " ", count: lineNumberWidth)) ...")
            for lineIndex in (newSuffixIndex + 1)..<trailingContextEnd {
                output.append(" \(String(lineIndex + 1).padLeft(to: lineNumberWidth)) \(newLines[lineIndex])")
            }
        }

        return EditDiffResult(diff: output.joined(separator: "\n"), firstChangedLine: firstChangedLine)
    }

    private func truncateHead(_ content: String, maxLines: Int, maxBytes: Int) -> GeminiToolTruncation {
        let totalBytes = byteCount(of: content)
        let lines = content.components(separatedBy: "\n")
        let totalLines = lines.count

        if totalLines <= maxLines && totalBytes <= maxBytes {
            return GeminiToolTruncation(
                content: content,
                truncated: false,
                truncatedBy: nil,
                totalLines: totalLines,
                totalBytes: totalBytes,
                outputLines: totalLines,
                outputBytes: totalBytes,
                firstLineExceedsLimit: false,
                maxLines: maxLines,
                maxBytes: maxBytes
            )
        }

        let firstLineBytes = byteCount(of: lines.first ?? "")
        if firstLineBytes > maxBytes {
            return GeminiToolTruncation(
                content: "",
                truncated: true,
                truncatedBy: "bytes",
                totalLines: totalLines,
                totalBytes: totalBytes,
                outputLines: 0,
                outputBytes: 0,
                firstLineExceedsLimit: true,
                maxLines: maxLines,
                maxBytes: maxBytes
            )
        }

        var outputLines: [String] = []
        var outputBytesCount = 0
        var truncatedBy = "lines"

        for (index, line) in lines.enumerated() where index < maxLines {
            let lineBytes = byteCount(of: line) + (index > 0 ? 1 : 0)
            if outputBytesCount + lineBytes > maxBytes {
                truncatedBy = "bytes"
                break
            }
            outputLines.append(line)
            outputBytesCount += lineBytes
        }

        if outputLines.count >= maxLines && outputBytesCount <= maxBytes {
            truncatedBy = "lines"
        }

        let outputContent = outputLines.joined(separator: "\n")
        return GeminiToolTruncation(
            content: outputContent,
            truncated: true,
            truncatedBy: truncatedBy,
            totalLines: totalLines,
            totalBytes: totalBytes,
            outputLines: outputLines.count,
            outputBytes: byteCount(of: outputContent),
            firstLineExceedsLimit: false,
            maxLines: maxLines,
            maxBytes: maxBytes
        )
    }

    private func locateExecutable(named name: String) -> String? {
        let searchPaths = (
            ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        ) + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func runCommand(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        currentDirectoryURL: URL? = nil
    ) -> GeminiToolCommandOutput {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
        } catch {
            return GeminiToolCommandOutput(
                exitCode: -1,
                stdout: "",
                stderr: "",
                timedOut: false,
                runError: error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while task.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if task.isRunning {
            timedOut = true
            task.terminate()
        }

        task.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return GeminiToolCommandOutput(
            exitCode: Int(task.terminationStatus),
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut,
            runError: nil
        )
    }

    private func collectRipgrepMatches(from jsonOutput: String, limit: Int) -> (items: [GrepMatch], limitReached: Bool) {
        var items: [GrepMatch] = []
        let lines = jsonOutput.split(whereSeparator: \.isNewline)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String,
                  type == "match",
                  let payload = event["data"] as? [String: Any],
                  let pathPayload = payload["path"] as? [String: Any],
                  let filePath = pathPayload["text"] as? String,
                  let lineNumber = payload["line_number"] as? Int else {
                continue
            }

            items.append(GrepMatch(filePath: filePath, lineNumber: lineNumber))
            if items.count >= limit {
                return (items, true)
            }
        }
        return (items, false)
    }

    private func formatGrepOutput(
        matches: [GrepMatch],
        searchRoot: URL,
        searchPathIsDirectory: Bool,
        context: Int
    ) -> (output: String, matches: [[String: Any]], linesTruncated: Bool) {
        var renderedLines: [String] = []
        var renderedMatches: [[String: Any]] = []
        var fileCache: [String: [String]] = [:]
        var linesTruncated = false

        func fileLines(for filePath: String) -> [String] {
            if let cached = fileCache[filePath] {
                return cached
            }
            let text = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            fileCache[filePath] = lines
            return lines
        }

        func displayPath(for filePath: String) -> String {
            let fileURL = URL(fileURLWithPath: filePath)
            if searchPathIsDirectory {
                let relative = fileURL.path.replacingOccurrences(of: searchRoot.path + "/", with: "")
                if relative != fileURL.path {
                    return relative.replacingOccurrences(of: "\\", with: "/")
                }
            }
            return fileURL.lastPathComponent
        }

        for match in matches {
            let lines = fileLines(for: match.filePath)
            let relativePath = displayPath(for: match.filePath)
            if lines.isEmpty {
                renderedLines.append("\(relativePath):\(match.lineNumber): (unable to read file)")
                renderedMatches.append([
                    "path": relativePath,
                    "line": match.lineNumber,
                    "preview": "(unable to read file)"
                ])
                continue
            }

            let start = max(1, match.lineNumber - context)
            let end = min(lines.count, match.lineNumber + context)

            for current in start...end {
                let rawLine = (lines[current - 1]).replacingOccurrences(of: "\r", with: "")
                let truncated = truncateLine(rawLine, maxCharacters: grepMaxLineLength)
                if truncated.wasTruncated {
                    linesTruncated = true
                }

                if current == match.lineNumber {
                    renderedLines.append("\(relativePath):\(current): \(truncated.text)")
                    renderedMatches.append([
                        "path": relativePath,
                        "line": current,
                        "preview": truncated.text
                    ])
                } else {
                    renderedLines.append("\(relativePath)-\(current)- \(truncated.text)")
                }
            }
        }

        return (renderedLines.joined(separator: "\n"), renderedMatches, linesTruncated)
    }

    private func truncateLine(_ line: String, maxCharacters: Int) -> (text: String, wasTruncated: Bool) {
        guard line.count > maxCharacters else {
            return (line, false)
        }

        let endIndex = line.index(line.startIndex, offsetBy: maxCharacters)
        return (String(line[..<endIndex]) + "... [truncated]", true)
    }

    private func byteCount(of string: String) -> Int {
        string.lengthOfBytes(using: .utf8)
    }

    private func openClawReportedWriteSize(of string: String) -> Int {
        string.utf16.count
    }

    private func formatRoundedBytes(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1fMB", Double(bytes) / Double(1024 * 1024))
        }
        if bytes >= 1024 {
            return "\(Int(round(Double(bytes) / 1024.0)))KB"
        }
        return "\(bytes)B"
    }

    private func formatOpenClawSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        }
        if bytes < 1024 * 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        }
        return String(format: "%.1fMB", Double(bytes) / Double(1024 * 1024))
    }

    private func locateFindExecutable() -> String? {
        locateExecutable(named: "fd") ?? locateExecutable(named: "fdfind")
    }

    private func runFindWithFD(
        executablePath: String,
        pattern: String,
        searchRoot: URL,
        limit: Int
    ) -> (matches: [String], error: String?) {
        let process = runCommand(
            executablePath: executablePath,
            arguments: [
                "--glob",
                "--color=never",
                "--hidden",
                "--max-results",
                String(limit),
                pattern,
                ".",
            ],
            timeout: 15,
            currentDirectoryURL: searchRoot
        )

        if let runError = process.runError {
            return ([], "Failed to run fd: \(runError)")
        }
        if process.timedOut {
            return ([], "fd timed out.")
        }

        let lines = process.stdout.components(separatedBy: .newlines)
        var matches: [String] = []
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var relativePath = trimmed.replacingOccurrences(of: "\\", with: "/")
            if relativePath.hasPrefix("./") {
                relativePath.removeFirst(2)
            }
            guard !relativePath.isEmpty else { continue }

            matches.append(relativePath)
        }

        if process.exitCode != 0 && matches.isEmpty {
            let stderr = process.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return ([], stderr.isEmpty ? "fd exited with code \(process.exitCode)." : stderr)
        }

        return (matches, nil)
    }

    private func fallbackFindMatches(pattern: String, searchRoot: URL, limit: Int) -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var matches: [String] = []
        for case let itemURL as URL in enumerator {
            let lastComponent = itemURL.lastPathComponent
            if lastComponent == ".git" || lastComponent == "node_modules" {
                enumerator.skipDescendants()
                continue
            }

            let relativePath = relativePath(from: searchRoot, to: itemURL)
            guard !relativePath.isEmpty else { continue }

            if globMatches(pattern: pattern, candidate: relativePath) {
                matches.append(relativePath)
            }
        }

        return matches
    }

    private func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.resolvingSymlinksInPath().path
        let targetPath = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard targetPath != basePath else { return "" }
        guard targetPath.hasPrefix(basePath + "/") else {
            return targetURL.lastPathComponent.replacingOccurrences(of: "\\", with: "/")
        }
        return String(targetPath.dropFirst(basePath.count + 1)).replacingOccurrences(of: "\\", with: "/")
    }

    private func globMatches(pattern: String, candidate: String) -> Bool {
        let normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/")
        let normalizedCandidate = candidate.replacingOccurrences(of: "\\", with: "/")

        if !normalizedPattern.contains("/") {
            return globSegmentMatches(
                pattern: normalizedPattern,
                candidate: URL(fileURLWithPath: normalizedCandidate).lastPathComponent
            )
        }

        let patternSegments = normalizedPattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let candidateSegments = normalizedCandidate.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return globPathMatches(
            patternSegments: patternSegments,
            candidateSegments: candidateSegments,
            patternIndex: 0,
            candidateIndex: 0
        )
    }

    private func globPathMatches(
        patternSegments: [String],
        candidateSegments: [String],
        patternIndex: Int,
        candidateIndex: Int
    ) -> Bool {
        if patternIndex == patternSegments.count {
            return candidateIndex == candidateSegments.count
        }

        let segment = patternSegments[patternIndex]
        if segment == "**" {
            if patternIndex + 1 == patternSegments.count {
                return true
            }

            for nextCandidateIndex in candidateIndex...candidateSegments.count {
                if globPathMatches(
                    patternSegments: patternSegments,
                    candidateSegments: candidateSegments,
                    patternIndex: patternIndex + 1,
                    candidateIndex: nextCandidateIndex
                ) {
                    return true
                }
            }
            return false
        }

        guard candidateIndex < candidateSegments.count else { return false }
        guard globSegmentMatches(pattern: segment, candidate: candidateSegments[candidateIndex]) else {
            return false
        }

        return globPathMatches(
            patternSegments: patternSegments,
            candidateSegments: candidateSegments,
            patternIndex: patternIndex + 1,
            candidateIndex: candidateIndex + 1
        )
    }

    private func globSegmentMatches(pattern: String, candidate: String) -> Bool {
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escapedPattern
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let range = NSRange(location: 0, length: (candidate as NSString).length)
        return regex.firstMatch(in: candidate, range: range) != nil
    }

    private func resolveHostPathCandidate(
        trimmedPath: String,
        baseDirectory: URL,
        allowRelative: Bool,
        directoryHint: Bool?,
        preferExistingReadVariant: Bool
    ) -> URL? {
        let candidate: URL
        if trimmedPath.hasPrefix("/") || trimmedPath.hasPrefix("~") {
            let expanded = (trimmedPath as NSString).expandingTildeInPath
            candidate = URL(fileURLWithPath: expanded, isDirectory: directoryHint ?? false)
        } else {
            guard allowRelative else { return nil }
            candidate = baseDirectory.appendingPathComponent(trimmedPath, isDirectory: directoryHint ?? false)
        }

        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard preferExistingReadVariant else {
            return resolvedCandidate
        }

        return preferredReadableVariant(for: resolvedCandidate)
    }

    private func preferredReadableVariant(for candidate: URL) -> URL {
        for candidatePath in readPathVariants(for: candidate.path) {
            let variant = URL(fileURLWithPath: candidatePath, isDirectory: candidate.hasDirectoryPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if fileManager.fileExists(atPath: variant.path) {
                return variant
            }
        }
        return candidate
    }

    private func readPathVariants(for path: String) -> [String] {
        var variants: [String] = []

        func append(_ candidate: String) {
            guard !candidate.isEmpty else { return }
            guard !variants.contains(candidate) else { return }
            variants.append(candidate)
        }

        append(path)

        let amPmVariant = path.replacingOccurrences(
            of: " (AM|PM)\\.",
            with: "\(Self.narrowNoBreakSpace)$1.",
            options: .regularExpression
        )
        append(amPmVariant)

        let nfdVariant = path.decomposedStringWithCanonicalMapping
        append(nfdVariant)

        let curlyVariant = path.replacingOccurrences(of: "'", with: "\u{2019}")
        append(curlyVariant)

        let nfdCurlyVariant = nfdVariant.replacingOccurrences(of: "'", with: "\u{2019}")
        append(nfdCurlyVariant)

        return variants
    }

    private func prepareReadableFile(path: String) -> ReadableFileResolution {
        guard let fileURL = resolvedReadablePath(from: path) else {
            return .denied
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return .error(["success": false, "error": "File does not exist: \(path)"])
        }
        guard !isDirectory.boolValue else {
            return .error(["success": false, "error": "Path is a directory, not a file: \(path)"])
        }

        return .success(
            ReadableFile(
                url: fileURL,
                relativePath: workspaceRelativePath(for: fileURL),
                imageMimeType: detectSupportedImageMimeType(from: fileURL),
                pdfMimeType: detectPDFMimeType(from: fileURL)
            )
        )
    }

    private func detectSupportedImageMimeType(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4_100) else {
            return nil
        }
        return detectSupportedImageMimeType(from: header)
    }

    private func detectSupportedImageMimeType(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if data.count >= 8, Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
            return "image/png"
        }
        if data.count >= 3, Array(data.prefix(3)) == [0xFF, 0xD8, 0xFF] {
            return "image/jpeg"
        }
        if data.count >= 6 {
            let prefix = String(decoding: data.prefix(6), as: UTF8.self)
            if prefix == "GIF87a" || prefix == "GIF89a" {
                return "image/gif"
            }
        }
        if data.count >= 12,
           String(decoding: data.prefix(4), as: UTF8.self) == "RIFF",
           String(decoding: data[8..<12], as: UTF8.self) == "WEBP" {
            return "image/webp"
        }
        return nil
    }

    private func detectPDFMimeType(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 5) else { return nil }
        return detectPDFMimeType(from: header)
    }

    private func detectPDFMimeType(from data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        // PDF magic bytes: %PDF-
        if Array(data.prefix(5)) == [0x25, 0x50, 0x44, 0x46, 0x2D] {
            return "application/pdf"
        }
        return nil
    }

    private func prepareInlineImagePayload(data: Data, mimeType: String) -> PreparedInlineImage? {
        guard Self.supportedImageMimeTypes.contains(mimeType) else {
            return nil
        }

        let originalBase64 = data.base64EncodedString()
        let inputBase64Bytes = byteCount(of: originalBase64)
        guard let originalImage = decodeImage(data: data) else {
            guard inputBase64Bytes < inlineImageMaxBytes else { return nil }
            return PreparedInlineImage(
                data: originalBase64,
                mimeType: mimeType,
                originalWidth: 0,
                originalHeight: 0,
                width: 0,
                height: 0,
                wasResized: false
            )
        }

        let originalWidth = originalImage.width
        let originalHeight = originalImage.height

        if Self.supportedGeminiInlineImageMimeTypes.contains(mimeType),
           originalWidth <= inlineImageMaxDimension,
           originalHeight <= inlineImageMaxDimension,
           inputBase64Bytes < inlineImageMaxBytes {
            return PreparedInlineImage(
                data: originalBase64,
                mimeType: mimeType,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                width: originalWidth,
                height: originalHeight,
                wasResized: false
            )
        }

        let aspectFit = fittedSize(
            width: originalWidth,
            height: originalHeight,
            maxWidth: inlineImageMaxDimension,
            maxHeight: inlineImageMaxDimension
        )
        let qualitySteps = uniquePreservingOrder([jpegQuality, 85, 70, 55, 40])
        var currentWidth = max(1, aspectFit.width)
        var currentHeight = max(1, aspectFit.height)

        while true {
            guard let cgImage = scaleImage(data: data, maxPixelSize: max(currentWidth, currentHeight)) else {
                break
            }

            let actualWidth = cgImage.width
            let actualHeight = cgImage.height

            if let pngCandidate = encodeImage(cgImage, as: .png, quality: nil),
                   let prepared = makePreparedInlineImage(
                       encodedData: pngCandidate,
                       mimeType: "image/png",
                       originalWidth: originalWidth,
                       originalHeight: originalHeight,
                       width: actualWidth,
                        height: actualHeight,
                        wasResized: true
                   ) {
                return prepared
            }

            for quality in qualitySteps {
                if let jpegCandidate = encodeImage(cgImage, as: .jpeg, quality: quality),
                   let prepared = makePreparedInlineImage(
                       encodedData: jpegCandidate,
                       mimeType: "image/jpeg",
                       originalWidth: originalWidth,
                       originalHeight: originalHeight,
                       width: actualWidth,
                        height: actualHeight,
                        wasResized: true
                   ) {
                return prepared
            }
            }

            if currentWidth == 1 && currentHeight == 1 {
                break
            }

            let nextWidth = currentWidth == 1 ? 1 : max(1, Int(floor(Double(currentWidth) * 0.75)))
            let nextHeight = currentHeight == 1 ? 1 : max(1, Int(floor(Double(currentHeight) * 0.75)))
            if nextWidth == currentWidth && nextHeight == currentHeight {
                break
            }
            currentWidth = nextWidth
            currentHeight = nextHeight
        }

        return nil
    }

    private func makePreparedInlineImage(
        encodedData: Data,
        mimeType: String,
        originalWidth: Int,
        originalHeight: Int,
        width: Int,
        height: Int,
        wasResized: Bool
    ) -> PreparedInlineImage? {
        let base64 = encodedData.base64EncodedString()
        guard byteCount(of: base64) < inlineImageMaxBytes else { return nil }
        return PreparedInlineImage(
            data: base64,
            mimeType: mimeType,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            width: width,
            height: height,
            wasResized: wasResized
        )
    }

    private func decodeImage(data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        guard let width, let height else { return nil }
        return (width, height)
    }

    private func scaleImage(data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func encodeImage(_ image: CGImage, as format: NSBitmapImageRep.FileType, quality: Int?) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if let quality, format == .jpeg {
            properties[.compressionFactor] = max(0.0, min(1.0, Double(quality) / 100.0))
        }
        return bitmap.representation(using: format, properties: properties)
    }

    private func imageReadText(mimeType: String, metadata: PreparedInlineImage) -> String {
        var text = "Read image file [\(mimeType)]"
        if metadata.wasResized,
           metadata.width > 0,
           metadata.height > 0,
           metadata.originalWidth > 0,
           metadata.originalHeight > 0 {
            let scale = Double(metadata.originalWidth) / Double(metadata.width)
            text += "\n[Image: original \(metadata.originalWidth)x\(metadata.originalHeight), displayed at \(metadata.width)x\(metadata.height). Multiply coordinates by \(String(format: "%.2f", scale)) to map to original image.]"
        }
        return text
    }

    private func normalizePathInput(_ rawPath: String?) -> String {
        var trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        for unicodeSpace in Self.unicodeSpaceVariants {
            trimmed = trimmed.replacingOccurrences(of: unicodeSpace, with: " ")
        }
        return trimmed
    }

    private func fittedSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int) -> (width: Int, height: Int) {
        var targetWidth = max(width, 1)
        var targetHeight = max(height, 1)

        if targetWidth > maxWidth {
            targetHeight = Int(round(Double(targetHeight) * Double(maxWidth) / Double(targetWidth)))
            targetWidth = maxWidth
        }
        if targetHeight > maxHeight {
            targetWidth = Int(round(Double(targetWidth) * Double(maxHeight) / Double(targetHeight)))
            targetHeight = maxHeight
        }

        return (max(targetWidth, 1), max(targetHeight, 1))
    }

    private func uniquePreservingOrder(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        var result: [Int] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }
}

private struct GeminiToolTruncation {
    let content: String
    let truncated: Bool
    let truncatedBy: String?
    let totalLines: Int
    let totalBytes: Int
    let outputLines: Int
    let outputBytes: Int
    let firstLineExceedsLimit: Bool
    let maxLines: Int
    let maxBytes: Int

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "truncated": truncated,
            "totalLines": totalLines,
            "totalBytes": totalBytes,
            "outputLines": outputLines,
            "outputBytes": outputBytes,
            "firstLineExceedsLimit": firstLineExceedsLimit,
            "maxLines": maxLines,
            "maxBytes": maxBytes
        ]
        if let truncatedBy {
            result["truncatedBy"] = truncatedBy
        }
        return result
    }
}

private struct GeminiToolCommandOutput {
    let exitCode: Int
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let runError: String?
}

private struct GrepMatch {
    let filePath: String
    let lineNumber: Int
}

private enum ReadableFileResolution {
    case denied
    case error([String: Any])
    case success(ReadableFile)
}

private struct ReadableFile {
    let url: URL
    let relativePath: String
    let imageMimeType: String?
    let pdfMimeType: String?
}

private struct PreparedInlineImage {
    let data: String
    let mimeType: String
    let originalWidth: Int
    let originalHeight: Int
    let width: Int
    let height: Int
    let wasResized: Bool

    var contentBlock: [String: Any] {
        [
            "type": "image",
            "data": data,
            "mimeType": mimeType,
        ]
    }

    var dictionary: [String: Any] {
        [
            "data": data,
            "mimeType": mimeType,
            "originalWidth": originalWidth,
            "originalHeight": originalHeight,
            "width": width,
            "height": height,
            "wasResized": wasResized,
        ]
    }
}

private struct FunctionResponseAttachment {
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

private struct AppliedEditContent {
    let baseContent: String
    let newContent: String
}

private struct FuzzyEditMatch {
    let found: Bool
    let index: Int
    let matchLength: Int
    let usedFuzzyMatch: Bool
}

private struct MatchedEdit {
    let editIndex: Int
    let matchIndex: Int
    let matchLength: Int
    let newText: String
}

private struct EditDiffResult {
    let diff: String
    let firstChangedLine: Int?
}

private extension String {
    func padLeft(to width: Int, with character: Character = " ") -> String {
        guard count < width else { return self }
        return String(repeating: String(character), count: width - count) + self
    }
}

private struct ReadSlice {
    let url: URL?
    let relativePath: String?
    let encoding: String?
    let offset: Int
    let limit: Int?
    let totalLines: Int
    let lineStart: Int
    let lineEnd: Int
    let primaryText: String
    let noticeText: String?
    let continuationOffset: Int?
    let truncation: GeminiToolTruncation?
    let firstLineExceedsLimit: Bool
    let payload: [String: Any]
    let isErrorPayload: Bool

    init(
        url: URL,
        relativePath: String,
        encoding: String,
        offset: Int,
        limit: Int?,
        totalLines: Int,
        lineStart: Int,
        lineEnd: Int,
        primaryText: String,
        noticeText: String?,
        continuationOffset: Int?,
        truncation: GeminiToolTruncation?,
        firstLineExceedsLimit: Bool
    ) {
        self.url = url
        self.relativePath = relativePath
        self.encoding = encoding
        self.offset = offset
        self.limit = limit
        self.totalLines = totalLines
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.primaryText = primaryText
        self.noticeText = noticeText
        self.continuationOffset = continuationOffset
        self.truncation = truncation
        self.firstLineExceedsLimit = firstLineExceedsLimit
        self.isErrorPayload = false

        var result: [String: Any] = [
            "success": true,
            "path": relativePath,
            "absolutePath": url.path,
            "content": Self.displayedText(primaryText: primaryText, noticeText: noticeText),
            "contentBlocks": [[
                "type": "text",
                "text": Self.displayedText(primaryText: primaryText, noticeText: noticeText),
            ]],
            "encoding": encoding,
            "offset": offset,
            "lineStart": lineStart,
            "lineEnd": lineEnd,
            "totalLines": totalLines
        ]
        if let limit {
            result["limit"] = limit
        }
        if let continuationOffset {
            result["continuationOffset"] = continuationOffset
        }
        if let truncation {
            result["truncation"] = truncation.dictionary
            result["details"] = ["truncation": truncation.dictionary]
        }
        if firstLineExceedsLimit {
            result["requiresExecFallback"] = true
        }
        self.payload = result
    }

    private init(errorPayload: [String: Any]) {
        url = nil
        relativePath = nil
        encoding = nil
        offset = 1
        limit = nil
        totalLines = 0
        lineStart = 0
        lineEnd = 0
        primaryText = ""
        noticeText = nil
        continuationOffset = nil
        truncation = nil
        firstLineExceedsLimit = false
        payload = errorPayload
        isErrorPayload = true
    }

    static func error(_ payload: [String: Any]) -> ReadSlice {
        ReadSlice(errorPayload: payload)
    }

    func materializePayload(
        overridingContent content: String?,
        overridingContinuationOffset continuationOffset: Int?,
        capped: Bool
    ) -> [String: Any] {
        guard !isErrorPayload else { return payload }

        var result = payload
        if let content {
            result["content"] = content
            result["contentBlocks"] = [[
                "type": "text",
                "text": content,
            ]]
        }
        if let continuationOffset {
            result["continuationOffset"] = continuationOffset
        } else if capped == false {
            result.removeValue(forKey: "continuationOffset")
        }
        result["capped"] = capped
        return result
    }

    private static func displayedText(primaryText: String, noticeText: String?) -> String {
        guard let noticeText, !noticeText.isEmpty else { return primaryText }
        guard !primaryText.isEmpty else { return noticeText }
        return primaryText + "\n\n" + noticeText
    }
}
