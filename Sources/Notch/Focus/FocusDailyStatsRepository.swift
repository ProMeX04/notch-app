import Foundation

struct FocusDailySyncEntry: Codable, Equatable {
    let date: String
    let focusSeconds: Int
    let sessionCount: Int

    enum CodingKeys: String, CodingKey {
        case date
        case focusSeconds = "focus_seconds"
        case sessionCount = "session_count"
    }
}

@MainActor
final class FocusDailyStatsRepository: ObservableObject {
    @Published private(set) var entries: [String: FocusDailySyncEntry]
    @Published private(set) var pendingDateKeys: Set<String>

    var onPendingDataChanged: (() -> Void)?

    private struct StoredState: Codable {
        let entries: [FocusDailySyncEntry]
        let pendingDateKeys: [String]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private static var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    init(fileURL: URL = FocusStoragePaths.dailyStatsV2URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let state = Self.loadState(from: fileURL)
        entries = Dictionary(uniqueKeysWithValues: state.entries.map { ($0.date, $0) })
        pendingDateKeys = Set(state.pendingDateKeys)
    }

    var pendingEntries: [FocusDailySyncEntry] {
        pendingDateKeys.compactMap { entries[$0] }.sorted { $0.date < $1.date }
    }

    func pendingSnapshot(limit: Int) -> [FocusDailySyncEntry] {
        Array(pendingEntries.prefix(max(limit, 0)))
    }

    func recordFocusedInterval(_ interval: DateInterval) {
        var remaining = max(Int(interval.duration.rounded(.down)), 0)
        guard remaining > 0 else { return }
        var cursor = interval.start

        while remaining > 0 {
            let dateKey = Self.dateKey(for: cursor)
            let dayStart = Self.utcCalendar.startOfDay(for: cursor)
            let nextDay = Self.utcCalendar.date(byAdding: .day, value: 1, to: dayStart)!
            let secondsUntilBoundary = max(Int(nextDay.timeIntervalSince(cursor).rounded(.up)), 1)
            let seconds = min(remaining, secondsUntilBoundary)
            update(dateKey: dateKey, addedSeconds: seconds, completedSessions: 0)
            remaining -= seconds
            cursor = cursor.addingTimeInterval(TimeInterval(seconds))
        }

        persistAndNotify()
    }

    func recordCompletedFocusSession(at date: Date) {
        update(dateKey: Self.dateKey(for: date), addedSeconds: 0, completedSessions: 1)
        persistAndNotify()
    }

    func acknowledgeSynced(_ snapshot: [FocusDailySyncEntry]) {
        var changed = false
        for sentEntry in snapshot where entries[sentEntry.date] == sentEntry {
            changed = pendingDateKeys.remove(sentEntry.date) != nil || changed
        }
        if changed { persist() }
    }

    private func update(dateKey: String, addedSeconds: Int, completedSessions: Int) {
        let existing = entries[dateKey]
        entries[dateKey] = FocusDailySyncEntry(
            date: dateKey,
            focusSeconds: (existing?.focusSeconds ?? 0) + addedSeconds,
            sessionCount: (existing?.sessionCount ?? 0) + completedSessions
        )
        pendingDateKeys.insert(dateKey)
    }

    private func persistAndNotify() {
        persist()
        onPendingDataChanged?()
    }

    private func persist() {
        let state = StoredState(
            entries: entries.values.sorted { $0.date < $1.date },
            pendingDateKeys: pendingDateKeys.sorted()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadState(from fileURL: URL) -> StoredState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return StoredState(entries: [], pendingDateKeys: [])
        }
        return state
    }

    static func dateKey(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

private enum FocusStoragePaths {
    static var dailyStatsV2URL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("Focus", isDirectory: true)
            .appendingPathComponent("daily-stats-v2.json")
    }
}
