import Foundation

/// Per-card spaced-repetition state (SM-2 inspired).
/// Proven ingredients: expanding intervals, ease adjustment, lapses on failure.
struct TOEICCardSchedule: Codable, Equatable, Hashable {
    /// Ease factor (SM-2 default 2.5). Clamped ≥ 1.3.
    var ease: Double
    /// Days until next review after last successful review.
    var intervalDays: Double
    /// Successful reviews in a row (reset on lapse).
    var repetitions: Int
    /// Times the card was failed after being learned.
    var lapses: Int
    /// Next due timestamp.
    var dueAt: Date
    var lastReviewedAt: Date?
    /// Last grade 0…5 (0–2 fail, 3 hard, 4 good, 5 easy).
    var lastGrade: Int?
    /// How many times the card has been seen (flip / quiz).
    var reviewCount: Int

    static let `default` = TOEICCardSchedule(
        ease: 2.5,
        intervalDays: 0,
        repetitions: 0,
        lapses: 0,
        dueAt: .distantPast,
        lastReviewedAt: nil,
        lastGrade: nil,
        reviewCount: 0
    )

    var isNew: Bool { reviewCount == 0 && repetitions == 0 && lastReviewedAt == nil }

    func isDue(at date: Date = Date()) -> Bool {
        dueAt <= date
    }
}

enum TOEICGrade: Int {
    /// Complete blackout / wrong answer.
    case again = 0
    /// Recalled with serious difficulty (kept for API completeness).
    case hard = 3
    /// Correct with some effort.
    case good = 4
    /// Correct effortlessly.
    case easy = 5

    var isFail: Bool { rawValue < 3 }
}

/// SM-2 style scheduler used for flashcards + quiz retrieval practice.
enum TOEICScheduler {
    /// Apply a grade and return the updated schedule.
    static func review(
        _ schedule: TOEICCardSchedule,
        grade: TOEICGrade,
        now: Date = Date()
    ) -> TOEICCardSchedule {
        var s = schedule
        s.lastReviewedAt = now
        s.lastGrade = grade.rawValue
        s.reviewCount += 1

        if grade.isFail {
            s.lapses += s.repetitions > 0 ? 1 : 0
            s.repetitions = 0
            s.intervalDays = 0
            // Relearn soon — same session / within ~10 minutes for short Focus loops.
            s.dueAt = now.addingTimeInterval(10 * 60)
            s.ease = max(1.3, s.ease - 0.20)
            return s
        }

        // Success path
        switch s.repetitions {
        case 0:
            s.intervalDays = grade == .easy ? 2 : 1
        case 1:
            s.intervalDays = grade == .easy ? 6 : (grade == .hard ? 3 : 4)
        default:
            let mult: Double
            switch grade {
            case .hard: mult = max(1.2, s.ease - 0.15)
            case .good: mult = s.ease
            case .easy: mult = s.ease * 1.3
            case .again: mult = 1 // unreachable
            }
            s.intervalDays = max(1, (s.intervalDays * mult).rounded())
        }

        s.repetitions += 1

        // SM-2 ease update (only on non-fail).
        let q = Double(grade.rawValue)
        s.ease = max(1.3, s.ease + (0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02)))

        let seconds = s.intervalDays * 24 * 60 * 60
        s.dueAt = now.addingTimeInterval(seconds)
        return s
    }

    /// Pick a study queue: due reviews first, then new cards (evidence: prioritise retrieval of aging items).
    /// Mix ratio ~70% due / 30% new when both available.
    static func selectCardIDs(
        allIDs: [String],
        schedules: [String: TOEICCardSchedule],
        limit: Int,
        now: Date = Date()
    ) -> [String] {
        let n = max(0, limit)
        guard n > 0, !allIDs.isEmpty else { return [] }

        var due: [(String, Date)] = []
        var fresh: [String] = []
        var later: [(String, Date)] = []

        for id in allIDs {
            let s = schedules[id] ?? .default
            if s.isNew {
                fresh.append(id)
            } else if s.isDue(at: now) {
                due.append((id, s.dueAt))
            } else {
                later.append((id, s.dueAt))
            }
        }

        due.sort { $0.1 < $1.1 } // most overdue first
        fresh.shuffle()
        later.sort { $0.1 < $1.1 }

        // 70% slots for due when possible
        let dueTarget = min(due.count, max(1, Int((Double(n) * 0.7).rounded())))
        var picked: [String] = due.prefix(dueTarget).map(\.0)

        let remaining = n - picked.count
        if remaining > 0 {
            let newTake = min(fresh.count, remaining)
            picked.append(contentsOf: fresh.prefix(newTake))
        }
        let still = n - picked.count
        if still > 0 {
            // Upcoming cards (not yet due) as filler — still better than pure random bank.
            picked.append(contentsOf: later.prefix(still).map(\.0))
        }
        if still > 0, picked.count < n {
            // Absolute fallback
            let leftover = allIDs.filter { !picked.contains($0) }.shuffled()
            picked.append(contentsOf: leftover.prefix(n - picked.count))
        }

        // Light shuffle of the assembled queue so reviews aren't strictly chronological
        // while keeping due-heavy composition (interleaving within the session).
        return interleavePreservePriority(picked)
    }

    /// Fisher-Yates on pairs: keeps approximate order of halves mixed.
    private static func interleavePreservePriority(_ ids: [String]) -> [String] {
        guard ids.count > 2 else { return ids }
        let mid = ids.count / 2
        let a = Array(ids.prefix(mid))
        let b = Array(ids.suffix(ids.count - mid)).shuffled()
        var out: [String] = []
        out.reserveCapacity(ids.count)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count { out.append(a[i]); i += 1 }
            if j < b.count { out.append(b[j]); j += 1 }
        }
        return out
    }

    /// Build an interleaved quiz list for selected word IDs (retrieval practice + interleaving).
    /// Prefer: for new cards → meaning first; for reviewed → cloze; avoid back-to-back same word.
    static func buildInterleavedQuiz(
        wordIDs: [String],
        allItems: [TOEICQuizItem],
        schedules: [String: TOEICCardSchedule],
        limit: Int
    ) -> [TOEICQuizItem] {
        let n = max(0, limit)
        guard n > 0 else { return [] }

        func numericID(from cardID: String) -> Int? {
            if cardID.hasPrefix("vocab-") { return Int(cardID.dropFirst(6)) }
            return Int(cardID)
        }

        func itemWordNum(_ item: TOEICQuizItem) -> Int? {
            let id = item.id
            if id.hasPrefix("ai-cloze-") { return Int(id.dropFirst(9)) }
            if id.hasPrefix("ai-meaning-") { return Int(id.dropFirst(11)) }
            if id.hasPrefix("cloze-") { return Int(id.dropFirst(6)) }
            if id.hasPrefix("meaning-") { return Int(id.dropFirst(8)) }
            return nil
        }

        // Index questions by word number
        var byWord: [Int: [TOEICQuizItem]] = [:]
        for item in allItems {
            guard let num = itemWordNum(item) else { continue }
            byWord[num, default: []].append(item)
        }

        var pool: [TOEICQuizItem] = []
        for cardID in wordIDs {
            guard let num = numericID(from: cardID), var options = byWord[num], !options.isEmpty else {
                continue
            }
            let schedule = schedules[cardID] ?? .default
            // Prefer AI meaning for new (retrieval of sense); AI cloze for mature (transfer).
            options.sort { a, b in
                let score: (TOEICQuizItem) -> Int = { item in
                    let id = item.id
                    let isAIMeaning = id.hasPrefix("ai-meaning-")
                    let isAICloze = id.hasPrefix("ai-cloze-")
                    let isMeaning = id.hasPrefix("meaning-")
                    if schedule.isNew {
                        if isAIMeaning { return 0 }
                        if isMeaning { return 1 }
                        if isAICloze { return 2 }
                        return 3
                    }
                    if isAICloze { return 0 }
                    if isAIMeaning { return 1 }
                    if id.hasPrefix("cloze-") { return 2 }
                    return 3
                }
                return score(a) < score(b)
            }
            // Take top 1–2 per word for variety without flooding
            pool.append(contentsOf: options.prefix(schedule.isNew ? 1 : 2))
        }

        // If thin, pad from global bank preferring due words' questions
        if pool.count < n {
            let extra = allItems.shuffled().filter { item in
                !pool.contains(where: { $0.id == item.id })
            }
            pool.append(contentsOf: extra.prefix(n - pool.count))
        }

        return spreadSameWord(Array(pool.prefix(max(n * 2, n))), limit: n)
    }

    /// Avoid consecutive questions on the same headword (interleaving).
    private static func spreadSameWord(_ items: [TOEICQuizItem], limit: Int) -> [TOEICQuizItem] {
        guard !items.isEmpty else { return [] }

        func wordKey(_ item: TOEICQuizItem) -> String {
            if item.id.hasPrefix("ai-cloze-") { return String(item.id.dropFirst(9)) }
            if item.id.hasPrefix("ai-meaning-") { return String(item.id.dropFirst(11)) }
            if item.id.hasPrefix("cloze-") { return String(item.id.dropFirst(6)) }
            if item.id.hasPrefix("meaning-") { return String(item.id.dropFirst(8)) }
            return item.id
        }

        var remaining = items
        var out: [TOEICQuizItem] = []
        var lastKey: String?

        while !remaining.isEmpty && out.count < limit {
            if let idx = remaining.firstIndex(where: { wordKey($0) != lastKey }) {
                let item = remaining.remove(at: idx)
                out.append(item)
                lastKey = wordKey(item)
            } else {
                // All left share the same word — append and break pattern
                let item = remaining.removeFirst()
                out.append(item)
                lastKey = wordKey(item)
            }
        }
        return out
    }
}
