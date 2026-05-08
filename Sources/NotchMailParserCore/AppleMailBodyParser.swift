import Foundation
import AppKit

struct MailMIMEPart {
    let headers: [String: String]
    let body: String
    let children: [MailMIMEPart]
}

public enum AppleMailBodyParser {
    public static func parseEMLX(_ data: Data) -> String? {
        guard let newline = data.firstIndex(of: 0x0A),
              let byteCountText = String(data: data[..<newline], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let byteCount = Int(byteCountText)
        else { return nil }

        let payloadStart = newline + 1
        guard data.count >= payloadStart + byteCount else { return nil }
        let payload = data[payloadStart..<(payloadStart + byteCount)]
        return parseRFC822(Data(payload))
    }

    public static func parseRFC822(_ data: Data) -> String? {
        guard let raw = decodeText(data, charset: "utf-8") ?? decodeText(data, charset: "iso-8859-1") else { return nil }
        let part = parseMIMEPart(raw)
        return normalizedBody(bestBody(in: part))
    }

    static func parseMIMEPart(_ raw: String) -> MailMIMEPart {
        let separatorRange = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n")
        guard let separatorRange else {
            return MailMIMEPart(headers: [:], body: raw, children: [])
        }

        let headerText = String(raw[..<separatorRange.lowerBound])
        let body = String(raw[separatorRange.upperBound...])
        let headers = parseHeaders(headerText)
        guard let boundary = contentTypeParameter("boundary", in: headers["content-type"] ?? "") else {
            return MailMIMEPart(headers: headers, body: body, children: [])
        }

        let children = splitMultipartBody(body, boundary: boundary).map(parseMIMEPart)
        return MailMIMEPart(headers: headers, body: body, children: children)
    }

    static func parseHeaders(_ text: String) -> [String: String] {
        var unfolded: [String] = []
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), let last = unfolded.popLast() {
                unfolded.append(last + " " + line.trimmingCharacters(in: .whitespaces))
            } else {
                unfolded.append(line)
            }
        }

        var headers: [String: String] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[String(key)] = value
        }
        return headers
    }

    static func splitMultipartBody(_ body: String, boundary: String) -> [String] {
        let marker = "--\(boundary)"
        var parts: [String] = []
        for section in body.components(separatedBy: marker).dropFirst() {
            if section.hasPrefix("--") { break }
            let trimmed = section.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts
    }

    static func bestBody(in part: MailMIMEPart) -> String? {
        if !part.children.isEmpty {
            let childBodies = part.children.compactMap(bestBody)
            return childBodies.first { !$0.isEmpty }
        }

        let contentType = (part.headers["content-type"] ?? "text/plain").lowercased()
        guard contentType.hasPrefix("text/plain") || contentType.hasPrefix("text/html") else { return nil }
        let disposition = (part.headers["content-disposition"] ?? "").lowercased()
        guard !disposition.hasPrefix("attachment") else { return nil }

        let charset = contentTypeParameter("charset", in: part.headers["content-type"] ?? "") ?? "utf-8"
        let transferEncoding = (part.headers["content-transfer-encoding"] ?? "").lowercased()
        guard let decodedData = decodedBodyData(part.body, transferEncoding: transferEncoding),
              let decodedText = decodeText(decodedData, charset: charset) ?? decodeText(decodedData, charset: "utf-8") ?? decodeText(decodedData, charset: "iso-8859-1")
        else { return nil }

        if contentType.hasPrefix("text/html") {
            return htmlToText(decodedText)
        }
        return decodedText
    }

    static func contentTypeParameter(_ name: String, in contentType: String) -> String? {
        for component in contentType.components(separatedBy: ";").dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pair.count == 2, pair[0].lowercased() == name.lowercased() else { continue }
            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }

    static func decodedBodyData(_ body: String, transferEncoding: String) -> Data? {
        switch transferEncoding {
        case "base64":
            let compact = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: compact)
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body.data(using: .utf8)
        }
    }

    static func decodeQuotedPrintable(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let scalars = Array(text.utf8)
        var index = 0
        while index < scalars.count {
            let byte = scalars[index]
            if byte == 61, index + 2 < scalars.count {
                let next = scalars[index + 1]
                let afterNext = scalars[index + 2]
                if next == 13 || next == 10 {
                    index += next == 13 && afterNext == 10 ? 3 : 2
                    continue
                }
                if let high = hexValue(next), let low = hexValue(afterNext) {
                    bytes.append(high * 16 + low)
                    index += 3
                    continue
                }
            }
            bytes.append(byte)
            index += 1
        }
        return Data(bytes)
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    static func decodeText(_ data: Data, charset: String) -> String? {
        let normalized = charset.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        switch normalized {
        case "utf-8", "utf8", "us-ascii", "ascii":
            return String(data: data, encoding: .utf8)
        case "iso-8859-1", "latin1", "latin-1":
            return String(data: data, encoding: .isoLatin1)
        case "windows-1252", "cp1252":
            return String(data: data, encoding: .windowsCP1252)
        default:
            return String(data: data, encoding: .utf8)
        }
    }

    static func htmlToText(_ html: String) -> String {
        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil
           ) {
            return attributed.string
        }
        return html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    static func normalizedBody(_ body: String?) -> String? {
        guard let body else { return nil }
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var normalized: [String] = []
        var previousBlank = false
        for line in lines {
            let isBlank = line.isEmpty
            if isBlank && previousBlank { continue }
            normalized.append(line)
            previousBlank = isBlank
        }
        let text = normalized.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
