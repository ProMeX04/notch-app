import Foundation

struct GeminiToolTruncation {
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

enum ReadableFileResolution {
    case denied
    case error([String: Any])
    case success(ReadableFile)
}

struct ReadableFile {
    let url: URL
    let relativePath: String
    let imageMimeType: String?
    let pdfMimeType: String?
}

struct PreparedInlineImage {
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

struct ReadSlice {
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
