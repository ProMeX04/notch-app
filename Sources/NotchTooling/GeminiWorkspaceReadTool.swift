import AppKit
import Quartz
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct GeminiWorkspaceReadTool {
    public static let defaultReadMaxLines = 2_000
    public static let defaultReadMaxBytes = 50 * 1024
    public static let defaultAdaptiveReadBudgetBytes = 50 * 1024
    public static let defaultGrepMaxLineLength = 500
    public static let defaultInlineImageMaxBytes = Int(4.5 * 1024 * 1024)
    public static let defaultInlinePDFMaxBytes = 20 * 1024 * 1024
    public static let defaultInlineImageMaxDimension = 2_000
    public static let defaultJPEGQuality = 80
    static let supportedGeminiInlineImageMimeTypes: Set<String> = [
        "image/png",
        "image/jpeg",
        "image/webp",
    ]
    static let supportedImageMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
    ]
    static let unicodeSpaceVariants = [
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
    static let narrowNoBreakSpace = "\u{202F}"

    public static let openClawReadToolDescription =
        "Read the contents of a file. Supports text files, images (jpg, png, gif, webp), and PDF documents. Images and PDFs are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
    public static let openClawReadPathParameterDescription =
        "Path to the file to read (relative or absolute)"
    public static let openClawReadOffsetParameterDescription =
        "Line number to start reading from (1-indexed)"
    public static let openClawReadLimitParameterDescription =
        "Maximum number of lines to read"
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

    let workspaceRoot: URL
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

    func truncateHead(_ content: String, maxLines: Int, maxBytes: Int) -> GeminiToolTruncation {
        let lines = content.components(separatedBy: "\n")
        let totalLines = lines.count
        let totalBytes = byteCount(of: content)

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

        var outputLines: [String] = []
        var outputBytes = 0
        var truncatedBy = totalLines > maxLines ? "lines" : "bytes"

        for line in lines.prefix(maxLines) {
            let separatorBytes = outputLines.isEmpty ? 0 : 1
            let nextBytes = byteCount(of: line) + separatorBytes
            guard outputBytes + nextBytes <= maxBytes else {
                truncatedBy = "bytes"
                break
            }
            outputLines.append(line)
            outputBytes += nextBytes
        }

        return GeminiToolTruncation(
            content: outputLines.joined(separator: "\n"),
            truncated: true,
            truncatedBy: truncatedBy,
            totalLines: totalLines,
            totalBytes: totalBytes,
            outputLines: outputLines.count,
            outputBytes: outputBytes,
            firstLineExceedsLimit: outputLines.isEmpty && !lines.isEmpty,
            maxLines: maxLines,
            maxBytes: maxBytes
        )
    }

    func byteCount(of string: String) -> Int {
        string.data(using: .utf8)?.count ?? 0
    }

    private func formatRoundedBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return "\(Int(kb.rounded()))KB"
        }
        let mb = kb / 1024
        return String(format: "%.1fMB", mb)
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

    func fittedSize(width: Int, height: Int, maxWidth: Int, maxHeight: Int) -> (width: Int, height: Int) {
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

    func uniquePreservingOrder(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        var result: [Int] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
        }
        return result
    }
}
