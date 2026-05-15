import AppKit
import Quartz
import Foundation
import ImageIO

extension GeminiWorkspaceReadTool {
    func executeImageRead(file: ReadableFile, mimeType: String) -> [String: Any] {
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

    static let pdfMaxPages = 10

    func executePDFRead(file: ReadableFile, mimeType: String, offset: Int, limit: Int) -> [String: Any] {
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


    func detectSupportedImageMimeType(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 4_100) else {
            return nil
        }
        return detectSupportedImageMimeType(from: header)
    }

    func detectSupportedImageMimeType(from data: Data) -> String? {
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

    func detectPDFMimeType(from fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 5) else { return nil }
        return detectPDFMimeType(from: header)
    }

    func detectPDFMimeType(from data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        // PDF magic bytes: %PDF-
        if Array(data.prefix(5)) == [0x25, 0x50, 0x44, 0x46, 0x2D] {
            return "application/pdf"
        }
        return nil
    }

    func prepareInlineImagePayload(data: Data, mimeType: String) -> PreparedInlineImage? {
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

    func makePreparedInlineImage(
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

    func decodeImage(data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        guard let width, let height else { return nil }
        return (width, height)
    }

    func scaleImage(data: Data, maxPixelSize: Int) -> CGImage? {
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

    func encodeImage(_ image: CGImage, as format: NSBitmapImageRep.FileType, quality: Int?) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if let quality, format == .jpeg {
            properties[.compressionFactor] = max(0.0, min(1.0, Double(quality) / 100.0))
        }
        return bitmap.representation(using: format, properties: properties)
    }

    func imageReadText(mimeType: String, metadata: PreparedInlineImage) -> String {
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

}
