import Foundation

/// Prebuilt multiple-choice items shipped in `Resources/TOEIC/toeic_quiz.json`.
/// Built offline from the vocabulary bank (cloze + meaning) — no runtime AI.
enum TOEICQuizBank {
    private struct QuizRow: Codable {
        let id: String
        let wordId: Int?
        let word: String?
        let type: String?
        let prompt: String
        let choices: [String]
        let correctIndex: Int
        let explanationVI: String?
        let translationVI: String?
        let part: String?
    }

    private static let cached: [TOEICQuizItem] = loadFromBundle()

    static var allItems: [TOEICQuizItem] { cached }

    static var count: Int { cached.count }

    /// Draw up to `limit` prebuilt questions, preferring words not yet known.
    /// Prefers AI cloze (`ai-cloze-`) over offline cloze, then meaning MCQs.
    static func draw(
        limit: Int,
        knownWordIDs: Set<String> = [],
        preferTypes: Set<String> = ["ai-cloze", "ai-meaning", "cloze", "meaning"]
    ) -> [TOEICQuizItem] {
        let n = max(0, limit)
        guard n > 0, !cached.isEmpty else { return [] }

        // Map vocab-id style "vocab-12" → numeric 12 for known matching.
        let knownNumeric: Set<Int> = Set(
            knownWordIDs.compactMap { id -> Int? in
                if id.hasPrefix("vocab-") { return Int(id.dropFirst(6)) }
                return Int(id)
            }
        )

        func wordNum(for item: TOEICQuizItem) -> Int? {
            let id = item.id
            if id.hasPrefix("ai-cloze-") { return Int(id.dropFirst(9)) }
            if id.hasPrefix("ai-meaning-") { return Int(id.dropFirst(11)) }
            if id.hasPrefix("cloze-") { return Int(id.dropFirst(6)) }
            if id.hasPrefix("meaning-") { return Int(id.dropFirst(8)) }
            return nil
        }

        func typeRank(_ id: String) -> Int {
            if id.hasPrefix("ai-cloze-") { return 0 }
            if id.hasPrefix("ai-meaning-") { return 1 }
            if id.hasPrefix("cloze-") { return 2 }
            if id.hasPrefix("meaning-") { return 3 }
            return 4
        }

        var preferred: [TOEICQuizItem] = []
        var rest: [TOEICQuizItem] = []

        for item in cached.shuffled() {
            if !preferTypes.isEmpty {
                let ok = preferTypes.contains { item.id.hasPrefix($0) }
                if !ok { continue }
            }
            if let num = wordNum(for: item), knownNumeric.contains(num) {
                rest.append(item)
            } else {
                preferred.append(item)
            }
        }

        preferred.sort { typeRank($0.id) < typeRank($1.id) }
        rest.sort { typeRank($0.id) < typeRank($1.id) }
        return Array((preferred + rest).prefix(n))
    }

    private static func loadFromBundle() -> [TOEICQuizItem] {
        let url =
            NotchResourceBundle.url(forResource: "toeic_quiz", withExtension: "json", subdirectory: "TOEIC")
            ?? NotchResourceBundle.url(forResource: "toeic_quiz", withExtension: "json")
            ?? Bundle.main.url(forResource: "toeic_quiz", withExtension: "json", subdirectory: "TOEIC")
            ?? Bundle.main.url(forResource: "toeic_quiz", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([QuizRow].self, from: data) else {
            return []
        }

        return rows.compactMap { row -> TOEICQuizItem? in
            let choices = row.choices.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard choices.count >= 2 else { return nil }
            let idx = min(max(0, row.correctIndex), choices.count - 1)
            let prompt = row.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return nil }
            return TOEICQuizItem(
                id: row.id,
                prompt: prompt,
                choices: Array(choices.prefix(4)),
                correctIndex: min(idx, 3),
                explanationVI: row.explanationVI ?? "",
                part: (row.part?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Vocab",
                translationVI: row.translationVI ?? ""
            )
        }
    }
}
