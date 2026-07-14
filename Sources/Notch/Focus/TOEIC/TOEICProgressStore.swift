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
        }
    }

    func markKnown(cardID: String, known: Bool) {
        mutate { s in
            if known {
                if !s.knownCardIDs.contains(cardID) {
                    s.knownCardIDs.append(cardID)
                }
                if !s.reviewedCardIDs.contains(cardID) {
                    s.reviewedCardIDs.append(cardID)
                }
            } else {
                s.knownCardIDs.removeAll { $0 == cardID }
            }
            s.dailyReviewCount += 1
        }
    }

    func recordQuiz(correct: Bool) {
        mutate { s in
            s.quizAnswered += 1
            if correct { s.quizCorrect += 1 }
            s.dailyReviewCount += 1
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
