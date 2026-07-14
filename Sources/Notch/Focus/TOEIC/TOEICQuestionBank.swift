import Foundation

/// Helpers for parsing AI / multi-choice option labels.
/// (Bundled Study4 permanent-question bank removed — quiz stems are AI-generated.)
enum TOEICQuestionBank {
    /// "(A) write" → "write"
    static func stripOptionLabel(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: #"^\(?[A-Da-d]\)?[.):]\s*"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func answerIndex(answer: String, choices: [String], rawOptions: [String]) -> Int? {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.count == 1, let scalar = a.uppercased().unicodeScalars.first {
            let idx = Int(scalar.value) - Int(UnicodeScalar("A").value)
            if choices.indices.contains(idx) { return idx }
        }
        let cleaned = stripOptionLabel(a)
        if let i = choices.firstIndex(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
            return i
        }
        if let i = rawOptions.firstIndex(where: {
            $0.localizedCaseInsensitiveContains(a)
                || stripOptionLabel($0).caseInsensitiveCompare(cleaned) == .orderedSame
        }) {
            return i
        }
        return nil
    }
}
