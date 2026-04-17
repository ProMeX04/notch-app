import Foundation

enum LearningActivitySource: String, Codable, CaseIterable {
    case pomodoro

    var title: String {
        "Pomodoro"
    }
}

struct LearningSessionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let source: LearningActivitySource
    let seconds: Int
    let createdAt: Date
}

@MainActor
protocol LearningStatsRecording: AnyObject {
    func record(seconds: Int, source: LearningActivitySource)
}

@MainActor
final class LearningStatsStore: ObservableObject, LearningStatsRecording {
    @Published private(set) var entries: [LearningSessionEntry]

    private let userDefaults: UserDefaults
    private let calendar: Calendar

    init(userDefaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.userDefaults = userDefaults
        self.calendar = calendar
        entries = Self.loadEntries(from: userDefaults)
    }

    var totalLearningSeconds: Int {
        entries.reduce(0) { $0 + $1.seconds }
    }

    var todayLearningSeconds: Int {
        entries.reduce(0) { partialResult, entry in
            partialResult + (calendar.isDateInToday(entry.createdAt) ? entry.seconds : 0)
        }
    }

    var last7DaysSeconds: Int {
        let cutoffDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .distantPast
        return entries.reduce(0) { partialResult, entry in
            partialResult + (entry.createdAt >= cutoffDate ? entry.seconds : 0)
        }
    }

    var totalSessions: Int {
        entries.count
    }

    var averageSessionSeconds: Int {
        guard !entries.isEmpty else { return 0 }
        return totalLearningSeconds / entries.count
    }

    var streakDays: Int {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        guard !activeDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: .now)

        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        if streak > 0 {
            return streak
        }

        guard let latestActiveDay = activeDays.max() else { return 0 }
        cursor = latestActiveDay

        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    func record(seconds: Int, source: LearningActivitySource) {
        let clampedSeconds = max(seconds, 0)
        guard clampedSeconds > 0 else { return }

        if let idx = entries.firstIndex(where: { $0.source == source && calendar.isDate($0.createdAt, inSameDayAs: .now) }) {
            let existing = entries[idx]
            entries[idx] = LearningSessionEntry(
                id: existing.id,
                source: source,
                seconds: existing.seconds + clampedSeconds,
                createdAt: .now
            )
        } else {
            let entry = LearningSessionEntry(
                id: UUID(),
                source: source,
                seconds: clampedSeconds,
                createdAt: .now
            )
            entries.insert(entry, at: 0)
        }

        if entries.count > Self.maxStoredEntries {
            entries = Array(entries.prefix(Self.maxStoredEntries))
        }
        persistEntries()
    }

    func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }

        if minutes > 0 {
            return "\(minutes)m"
        }

        return "\(seconds)s"
    }

    private func persistEntries() {
        guard let encoded = try? JSONEncoder().encode(entries) else { return }
        userDefaults.set(encoded, forKey: Self.entriesDefaultsKey)
    }

    private static func loadEntries(from userDefaults: UserDefaults) -> [LearningSessionEntry] {
        guard let data = userDefaults.data(forKey: entriesDefaultsKey),
              let decodedEntries = try? JSONDecoder().decode([LearningSessionEntry].self, from: data) else {
            return []
        }

        return decodedEntries
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(maxStoredEntries)
            .map { $0 }
    }

    private static let entriesDefaultsKey = "NotchLearningEntries"
    private static let maxStoredEntries = 5000
}
