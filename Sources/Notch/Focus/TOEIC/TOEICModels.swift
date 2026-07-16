import Foundation

enum TOEICStudyMode: String, CaseIterable, Identifiable {
    case flashcards
    case quiz

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .quiz: return "Quiz"
        }
    }

    var icon: String {
        switch self {
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .quiz: return "list.bullet.rectangle"
        }
    }
}

struct TOEICVocabCard: Identifiable, Hashable, Codable {
    let id: String
    let word: String
    let phonetic: String
    let meaningVI: String
    let meaningEN: String
    let example: String
    let part: String // e.g. "Vocab", "Business"
}

struct TOEICQuizItem: Identifiable, Hashable, Codable {
    let id: String
    let prompt: String
    let choices: [String]
    let correctIndex: Int
    let explanationVI: String
    let part: String // "Part 5" style grammar/vocab
    /// Vietnamese translation of the completed sentence (shown under the question after answer).
    let translationVI: String

    init(
        id: String,
        prompt: String,
        choices: [String],
        correctIndex: Int,
        explanationVI: String,
        part: String,
        translationVI: String = ""
    ) {
        // Study4 / AI often packs "Dịch câu:" inside explanation — split so UI can show translation under the stem.
        let split = TOEICQuizText.splitExplanationAndTranslation(
            explanation: explanationVI,
            translation: translationVI
        )
        self.id = id
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
        self.explanationVI = split.explanation
        self.part = part
        self.translationVI = split.translation
    }
}

/// Shared helpers for TOEIC quiz copy (explanation vs translation).
enum TOEICQuizText {
    /// Line shown under the stem after the user answers — always prefer Vietnamese translation.
    /// Falls back to the English sentence with the blank filled so every cloze has something.
    static func lineUnderQuestion(for item: TOEICQuizItem) -> String {
        let split = splitExplanationAndTranslation(
            explanation: item.explanationVI,
            translation: item.translationVI
        )
        if !split.translation.isEmpty {
            return split.translation
        }
        let answer = item.choices.indices.contains(item.correctIndex)
            ? item.choices[item.correctIndex]
            : ""
        if let filled = completedSentence(prompt: item.prompt, answer: answer) {
            return filled
        }
        // Meaning-style quiz: show the correct choice (often the VI meaning).
        return answer
    }

    /// Replace `_____` / `___` with the correct option; nil if no blank in the prompt.
    static func completedSentence(prompt: String, answer: String) -> String? {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return nil }
        let s = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains("_____") {
            return s.replacingOccurrences(of: "_____", with: a)
        }
        if s.contains("___") {
            return s.replacingOccurrences(of: "___", with: a)
        }
        return nil
    }

    /// Prefer an explicit translation field; else peel "Dịch câu:" / "Dịch:" from explanation.
    static func splitExplanationAndTranslation(
        explanation: String,
        translation: String = ""
    ) -> (explanation: String, translation: String) {
        var exp = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        var trans = translation.trimmingCharacters(in: .whitespacesAndNewlines)

        let separators = [
            "Dịch câu:",
            "Dịch câu :",
            "Dịch cả câu:",
            "Dịch:",
            "Dịch nghĩa:",
            "Translation:",
            "translation:",
        ]

        if trans.isEmpty {
            for sep in separators {
                if let range = exp.range(of: sep, options: .caseInsensitive) {
                    let after = String(exp[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let before = String(exp[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    exp = before
                    // Drop junk like lone "TIẾP THEO" navigation leftovers from scrape.
                    if isUsefulTranslation(after) {
                        trans = cleanTranslation(after)
                    }
                    break
                }
            }
        } else {
            // Still strip a trailing "Dịch câu:" block from explanation if present.
            for sep in separators {
                if let range = exp.range(of: sep, options: .caseInsensitive) {
                    exp = String(exp[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            trans = cleanTranslation(trans)
        }

        // "Dịch đáp án:" is analysis, not sentence translation — leave in explanation.
        return (exp, trans)
    }

    private static func isUsefulTranslation(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }
        if t.count < 8 { return false }
        let junk: Set<String> = ["tiếp theo", "next", "→", "➤"]
        if junk.contains(t.lowercased()) { return false }
        // Single control / symbol lines
        if t.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) || $0.properties.isWhitespace }) {
            return false
        }
        return true
    }

    private static func cleanTranslation(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // First paragraph only (scrapes sometimes append more sections).
        if let blank = t.range(of: "\n\n") {
            t = String(t[..<blank.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Drop leading "Phân tích:" blocks if mis-split
        if t.lowercased().hasPrefix("phân tích") {
            return ""
        }
        return t
    }
}

struct TOEICProgressSnapshot: Codable, Equatable {
    var reviewedCardIDs: [String]
    var knownCardIDs: [String]
    var quizAnswered: Int
    var quizCorrect: Int
    var sessionsCompleted: Int
    var lastStudiedAt: Date?
    var dailyReviewCount: Int
    var dailyReviewDayKey: String
    /// Banked leisure minutes earned by studying (spent into Focus breaks).
    var leisureMinutesBalance: Int
    /// Lifetime leisure minutes earned from study.
    var leisureMinutesEarnedTotal: Int
    /// Lifetime leisure minutes applied to breaks.
    var leisureMinutesSpentTotal: Int
    /// Leisure minutes earned today (resets with dailyReviewDayKey).
    var leisureMinutesEarnedToday: Int
    /// SM-2 schedules keyed by card id (`vocab-123`).
    var cardSchedules: [String: TOEICCardSchedule]

    static let empty = TOEICProgressSnapshot(
        reviewedCardIDs: [],
        knownCardIDs: [],
        quizAnswered: 0,
        quizCorrect: 0,
        sessionsCompleted: 0,
        lastStudiedAt: nil,
        dailyReviewCount: 0,
        dailyReviewDayKey: "",
        leisureMinutesBalance: 0,
        leisureMinutesEarnedTotal: 0,
        leisureMinutesSpentTotal: 0,
        leisureMinutesEarnedToday: 0,
        cardSchedules: [:]
    )

    var accuracyPercent: Int {
        guard quizAnswered > 0 else { return 0 }
        return Int((Double(quizCorrect) / Double(quizAnswered) * 100).rounded())
    }

    var knownCount: Int { Set(knownCardIDs).count }
    var reviewedCount: Int { Set(reviewedCardIDs).count }

    var dueCount: Int {
        let now = Date()
        return cardSchedules.values.filter { $0.isDue(at: now) && !$0.isNew }.count
    }

    var newCount: Int {
        // Approximate: cards never scheduled are "new" relative to bank — UI uses store helper.
        cardSchedules.values.filter(\.isNew).count
    }

    enum CodingKeys: String, CodingKey {
        case reviewedCardIDs, knownCardIDs, quizAnswered, quizCorrect, sessionsCompleted
        case lastStudiedAt, dailyReviewCount, dailyReviewDayKey
        case leisureMinutesBalance, leisureMinutesEarnedTotal, leisureMinutesSpentTotal, leisureMinutesEarnedToday
        case cardSchedules
    }

    init(
        reviewedCardIDs: [String],
        knownCardIDs: [String],
        quizAnswered: Int,
        quizCorrect: Int,
        sessionsCompleted: Int,
        lastStudiedAt: Date?,
        dailyReviewCount: Int,
        dailyReviewDayKey: String,
        leisureMinutesBalance: Int,
        leisureMinutesEarnedTotal: Int,
        leisureMinutesSpentTotal: Int,
        leisureMinutesEarnedToday: Int,
        cardSchedules: [String: TOEICCardSchedule]
    ) {
        self.reviewedCardIDs = reviewedCardIDs
        self.knownCardIDs = knownCardIDs
        self.quizAnswered = quizAnswered
        self.quizCorrect = quizCorrect
        self.sessionsCompleted = sessionsCompleted
        self.lastStudiedAt = lastStudiedAt
        self.dailyReviewCount = dailyReviewCount
        self.dailyReviewDayKey = dailyReviewDayKey
        self.leisureMinutesBalance = leisureMinutesBalance
        self.leisureMinutesEarnedTotal = leisureMinutesEarnedTotal
        self.leisureMinutesSpentTotal = leisureMinutesSpentTotal
        self.leisureMinutesEarnedToday = leisureMinutesEarnedToday
        self.cardSchedules = cardSchedules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewedCardIDs = try c.decodeIfPresent([String].self, forKey: .reviewedCardIDs) ?? []
        knownCardIDs = try c.decodeIfPresent([String].self, forKey: .knownCardIDs) ?? []
        quizAnswered = try c.decodeIfPresent(Int.self, forKey: .quizAnswered) ?? 0
        quizCorrect = try c.decodeIfPresent(Int.self, forKey: .quizCorrect) ?? 0
        sessionsCompleted = try c.decodeIfPresent(Int.self, forKey: .sessionsCompleted) ?? 0
        lastStudiedAt = try c.decodeIfPresent(Date.self, forKey: .lastStudiedAt)
        dailyReviewCount = try c.decodeIfPresent(Int.self, forKey: .dailyReviewCount) ?? 0
        dailyReviewDayKey = try c.decodeIfPresent(String.self, forKey: .dailyReviewDayKey) ?? ""
        leisureMinutesBalance = try c.decodeIfPresent(Int.self, forKey: .leisureMinutesBalance) ?? 0
        leisureMinutesEarnedTotal = try c.decodeIfPresent(Int.self, forKey: .leisureMinutesEarnedTotal) ?? 0
        leisureMinutesSpentTotal = try c.decodeIfPresent(Int.self, forKey: .leisureMinutesSpentTotal) ?? 0
        leisureMinutesEarnedToday = try c.decodeIfPresent(Int.self, forKey: .leisureMinutesEarnedToday) ?? 0
        cardSchedules = try c.decodeIfPresent([String: TOEICCardSchedule].self, forKey: .cardSchedules) ?? [:]
    }
}

/// Study → leisure conversion rules (aligned with Block Shorts streak minutes, with a soft cap).
enum TOEICLeisureRewards {
    /// Max minutes granted for a single correct quiz answer.
    static let maxMinutesPerCorrectQuiz = 5
    /// Minutes for marking a flashcard as known.
    static let minutesPerKnownCard = 1

    /// Like Block Shorts: minutes = consecutive correct streak, capped.
    static func minutesForCorrectQuiz(streakAfterCorrect: Int) -> Int {
        max(0, min(streakAfterCorrect, maxMinutesPerCorrectQuiz))
    }
}
