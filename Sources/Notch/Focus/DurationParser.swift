import Foundation

/// Parses flexible duration strings into total seconds.
///
/// Supported formats (case-insensitive, units can be combined):
///   - "10m"          → 10 minutes
///   - "90s"          → 90 seconds
///   - "1h"           → 1 hour
///   - "1d"           → 1 day (24h)
///   - "1h30m"        → 1h 30m
///   - "1d 2h 30m"    → combined
///   - "1:30:00"      → h:mm:ss or mm:ss
///   - "90"           → plain number = minutes
///   - "1.5h"         → fractional hours (= 90 min)
///
/// Returns `nil` if nothing useful could be parsed.
enum DurationParser {
    static func parse(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try colon-separated format first: [h:]mm:ss or h:mm
        if let colon = parseColonFormat(trimmed) { return colon }

        // Try unit-based parsing
        if let units = parseUnitFormat(trimmed) { return units }

        // Plain number → treat as minutes
        if let plain = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            return max(1, Int(plain * 60))
        }

        return nil
    }

    // MARK: - Colon format

    private static func parseColonFormat(_ s: String) -> Int? {
        let parts = s.split(separator: ":").map { String($0) }
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        guard parts.allSatisfy({ Double($0) != nil }) else { return nil }

        let nums = parts.compactMap { Double($0) }
        switch nums.count {
        case 2: // mm:ss
            return Int(nums[0] * 60 + nums[1])
        case 3: // h:mm:ss
            return Int(nums[0] * 3600 + nums[1] * 60 + nums[2])
        default:
            return nil
        }
    }

    // MARK: - Unit format

    private static let unitPattern: NSRegularExpression? = {
        let pattern = #"(\d+(?:\.\d+)?)\s*(d|h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)"#
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    private static func parseUnitFormat(_ s: String) -> Int? {
        guard let regex = unitPattern else { return nil }

        let range = NSRange(s.startIndex..., in: s)
        let matches = regex.matches(in: s, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        var totalSeconds = 0

        for match in matches {
            guard
                let valueRange = Range(match.range(at: 1), in: s),
                let unitRange  = Range(match.range(at: 2), in: s),
                let value = Double(s[valueRange])
            else { continue }

            let unit = s[unitRange].lowercased()
            switch unit {
            case "d":
                totalSeconds += Int(value * 86400)
            case "h", "hr", "hrs", "hour", "hours":
                totalSeconds += Int(value * 3600)
            case "m", "min", "mins", "minute", "minutes":
                totalSeconds += Int(value * 60)
            case "s", "sec", "secs", "second", "seconds":
                totalSeconds += Int(value)
            default:
                break
            }
        }

        return totalSeconds > 0 ? totalSeconds : nil
    }

    // MARK: - Human-readable summary

    /// Returns a short display string like "1h 30m" or "45s" for a given second count.
    static func displayString(for totalSeconds: Int) -> String {
        guard totalSeconds > 0 else { return "0s" }

        let d = totalSeconds / 86400
        let h = (totalSeconds % 86400) / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60

        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }

        return parts.joined(separator: " ")
    }
}
