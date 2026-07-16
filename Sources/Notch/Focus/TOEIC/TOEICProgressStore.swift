import Combine
import Foundation

@MainActor
final class TOEICProgressStore: ObservableObject {
    static let shared = TOEICProgressStore()

    @Published private(set) var snapshot: TOEICProgressSnapshot = .empty

    private let defaults = UserDefaults.standard
    private let storageKey = "notch.toeic.progress.v1"

    private init() {
        load()
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func load() {
        guard let data = defaults.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode(TOEICProgressSnapshot.self, from: data) else {
            snapshot = .empty
            return
        }
        if decoded.dailyReviewDayKey != todayKey {
            decoded.dailyReviewCount = 0
            decoded.leisureMinutesEarnedToday = 0
            decoded.dailyReviewDayKey = todayKey
        }
        snapshot = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func mutate(_ body: (inout TOEICProgressSnapshot) -> Void) {
        var copy = snapshot
        if copy.dailyReviewDayKey != todayKey {
            copy.dailyReviewCount = 0
            copy.leisureMinutesEarnedToday = 0
            copy.dailyReviewDayKey = todayKey
        }
        // Backward-compat: older snapshots may decode missing leisure fields as 0 via defaults
        // if using custom decode; Codable synthesis needs defaults for new fields — use
        // decodeIfPresent in future if needed. Non-negative clamp:
        copy.leisureMinutesBalance = max(0, copy.leisureMinutesBalance)
        copy.leisureMinutesEarnedTotal = max(0, copy.leisureMinutesEarnedTotal)
        copy.leisureMinutesSpentTotal = max(0, copy.leisureMinutesSpentTotal)
        copy.leisureMinutesEarnedToday = max(0, copy.leisureMinutesEarnedToday)
        body(&copy)
        copy.lastStudiedAt = Date()
        snapshot = copy
        persist()
    }

    func markReviewed(cardID: String) {
        mutate { s in
            if !s.reviewedCardIDs.contains(cardID) {
                s.reviewedCardIDs.append(cardID)
            }
            s.dailyReviewCount += 1
            // Flipping is retrieval practice but not a graded review — touch count only.
            var sched = s.cardSchedules[cardID] ?? .default
            if sched.reviewCount == 0 {
                // First exposure: leave due immediately so it stays in today's queue.
                sched.dueAt = Date.distantPast
            }
            s.cardSchedules[cardID] = sched
        }
    }

    func markKnown(cardID: String, known: Bool) {
        gradeCard(cardID, grade: known ? .good : .again, alsoMarkKnown: known)
    }

    /// Apply SM-2 grade for a card (flashcard Know/Again or quiz outcome).
    func gradeCard(_ cardID: String, grade: TOEICGrade, alsoMarkKnown: Bool? = nil) {
        mutate { s in
            let previous = s.cardSchedules[cardID] ?? .default
            let updated = TOEICScheduler.review(previous, grade: grade)
            s.cardSchedules[cardID] = updated

            if !s.reviewedCardIDs.contains(cardID) {
                s.reviewedCardIDs.append(cardID)
            }
            s.dailyReviewCount += 1

            let markKnown = alsoMarkKnown ?? (grade == .good || grade == .easy)
            if markKnown {
                if !s.knownCardIDs.contains(cardID) {
                    s.knownCardIDs.append(cardID)
                }
            } else if grade.isFail {
                s.knownCardIDs.removeAll { $0 == cardID }
            }
        }
    }

    func recordQuiz(correct: Bool, cardID: String? = nil) {
        mutate { s in
            s.quizAnswered += 1
            if correct { s.quizCorrect += 1 }
            s.dailyReviewCount += 1

            // Retrieval practice grades the underlying word when mapped.
            guard let cardID else { return }
            let previous = s.cardSchedules[cardID] ?? .default
            let grade: TOEICGrade = correct ? .good : .again
            let updated = TOEICScheduler.review(previous, grade: grade)
            s.cardSchedules[cardID] = updated
            if !s.reviewedCardIDs.contains(cardID) {
                s.reviewedCardIDs.append(cardID)
            }
            if correct {
                if !s.knownCardIDs.contains(cardID) {
                    s.knownCardIDs.append(cardID)
                }
            } else {
                s.knownCardIDs.removeAll { $0 == cardID }
            }
        }
    }

    func schedule(for cardID: String) -> TOEICCardSchedule {
        snapshot.cardSchedules[cardID] ?? .default
    }

    /// Count cards due now among the full bank ids.
    func dueCount(in allIDs: [String], now: Date = Date()) -> Int {
        allIDs.reduce(0) { partial, id in
            let s = snapshot.cardSchedules[id] ?? .default
            return partial + ((s.isDue(at: now) && !s.isNew) ? 1 : 0)
        }
    }

    func newCount(in allIDs: [String]) -> Int {
        allIDs.reduce(0) { partial, id in
            let s = snapshot.cardSchedules[id] ?? .default
            return partial + (s.isNew ? 1 : 0)
        }
    }

    /// Credits leisure minutes from study. Returns minutes actually added.
    @discardableResult
    func earnLeisureMinutes(_ minutes: Int) -> Int {
        let grant = max(0, minutes)
        guard grant > 0 else { return 0 }
        mutate { s in
            s.leisureMinutesBalance += grant
            s.leisureMinutesEarnedTotal += grant
            s.leisureMinutesEarnedToday += grant
        }
        return grant
    }

    /// Spend up to `minutes` from the leisure bank. Returns minutes spent.
    @discardableResult
    func spendLeisureMinutes(_ minutes: Int) -> Int {
        let want = max(0, minutes)
        guard want > 0 else { return 0 }
        var spent = 0
        mutate { s in
            spent = min(want, s.leisureMinutesBalance)
            s.leisureMinutesBalance -= spent
            s.leisureMinutesSpentTotal += spent
        }
        return spent
    }

    /// Spend the entire balance (e.g. when a Focus break starts). Returns minutes spent.
    @discardableResult
    func spendAllLeisureMinutes() -> Int {
        spendLeisureMinutes(snapshot.leisureMinutesBalance)
    }

    func completeSession() {
        mutate { s in
            s.sessionsCompleted += 1
        }
    }

    func resetAll() {
        snapshot = .empty
        snapshot.dailyReviewDayKey = todayKey
        persist()
    }

    /// Merge reviewed/known IDs from Block Shorts mastery (does not wipe local-only IDs).
    func importExternal(reviewedIDs: [String], knownIDs: [String]) {
        mutate { s in
            var reviewed = Set(s.reviewedCardIDs)
            var known = Set(s.knownCardIDs)
            reviewed.formUnion(reviewedIDs)
            known.formUnion(knownIDs)
            s.reviewedCardIDs = Array(reviewed)
            s.knownCardIDs = Array(known)
        }
    }
}
