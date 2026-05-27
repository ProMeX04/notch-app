import Foundation
import NotchFocusFeature

struct LearningSessionEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let source: LearningActivitySource
    let seconds: Int
    let sessionCount: Int
    let createdAt: Date

    init(
        id: UUID,
        source: LearningActivitySource,
        seconds: Int,
        sessionCount: Int = 0,
        createdAt: Date
    ) {
        self.id = id
        self.source = source
        self.seconds = max(seconds, 0)
        self.sessionCount = max(sessionCount, 0)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case seconds
        case sessionCount
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(LearningActivitySource.self, forKey: .source)
        seconds = try container.decode(Int.self, forKey: .seconds)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

@MainActor
final class LearningStatsStore: ObservableObject, LearningStatsRecording {
    @Published private(set) var entries: [LearningSessionEntry]

    private let repository: LearningStatsRepository
    private let calendar: Calendar

    init(repository: LearningStatsRepository = LearningStatsRepository(), calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
        entries = repository.loadEntries().sorted { $0.createdAt > $1.createdAt }.prefix(Self.maxStoredEntries).map { $0 }
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
        entries.reduce(0) { $0 + $1.sessionCount }
    }

    var averageSessionSeconds: Int {
        guard totalSessions > 0 else { return 0 }
        return totalLearningSeconds / totalSessions
    }

    var streakDays: Int {
        let activeDays = Set(entries.filter { $0.seconds > 0 }.map { calendar.startOfDay(for: $0.createdAt) })
        guard !activeDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        if !activeDays.contains(cursor), let latestActiveDay = activeDays.max() {
            cursor = latestActiveDay
        }

        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }

    func recordFocusedInterval(_ interval: DateInterval, source: LearningActivitySource) {
        let seconds = max(Int(interval.duration.rounded(.down)), 0)
        guard seconds > 0 else { return }
        updateEntry(for: interval.end, source: source, addedSeconds: seconds, completedSessions: 0)
    }

    func recordCompletedFocusSession(at date: Date, source: LearningActivitySource) {
        updateEntry(for: date, source: source, addedSeconds: 0, completedSessions: 1)
    }

    func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    private func updateEntry(for date: Date, source: LearningActivitySource, addedSeconds: Int, completedSessions: Int) {
        if let index = entries.firstIndex(where: { $0.source == source && calendar.isDate($0.createdAt, inSameDayAs: date) }) {
            let existing = entries[index]
            entries[index] = LearningSessionEntry(
                id: existing.id,
                source: source,
                seconds: existing.seconds + addedSeconds,
                sessionCount: existing.sessionCount + completedSessions,
                createdAt: date
            )
        } else {
            entries.insert(
                LearningSessionEntry(
                    id: UUID(),
                    source: source,
                    seconds: addedSeconds,
                    sessionCount: completedSessions,
                    createdAt: date
                ),
                at: 0
            )
        }

        entries.sort { $0.createdAt > $1.createdAt }
        if entries.count > Self.maxStoredEntries {
            entries = Array(entries.prefix(Self.maxStoredEntries))
        }
        persistEntries()
    }

    private func persistEntries() {
        repository.save(entries)
    }

    private static let maxStoredEntries = 5000
}

final class LearningStatsRepository {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL = LearningStatsStoragePaths.entriesFile, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadEntries() -> [LearningSessionEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([LearningSessionEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func save(_ entries: [LearningSessionEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

private enum LearningStatsStoragePaths {
    static var entriesFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("Learning", isDirectory: true)
            .appendingPathComponent("stats.json")
    }
}
