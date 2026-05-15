import Foundation

public enum GeminiToolArgumentNormalizer {
    public static let pathKeys = ["path", "file_path", "filePath", "file"]

    public static func normalize(_ args: [String: Any]) -> [String: Any] {
        var normalized = args
        normalizeAliases(in: &normalized, canonical: "path", aliases: Array(pathKeys.dropFirst()))
        normalizeTextLikeValue(in: &normalized, key: "content")
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
