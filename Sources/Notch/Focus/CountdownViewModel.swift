import AppKit
import Foundation

@MainActor
final class CountdownViewModel: ObservableObject {
    @Published private(set) var presetSeconds: Int
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var hasActiveSession = false

    private var completionTask: Task<Void, Never>?
    private var endDate: Date?
    private let learningStatsStore: LearningStatsStore
    private var recordedSecondsForCurrentSession = 0

    /// Default preset options as seconds
    static let presetOptions: [Int] = [5 * 60, 10 * 60, 25 * 60, 45 * 60]

    init(learningStatsStore: LearningStatsStore) {
        self.learningStatsStore = learningStatsStore
        let defaultSeconds = Self.presetOptions[1]
        presetSeconds = defaultSeconds
        remainingSeconds = defaultSeconds
    }

    var showCompactIndicator: Bool {
        hasActiveSession || isRunning
    }

    var actionTitle: String {
        if isRunning {
            return "Pause"
        }
        return hasActiveSession ? "Resume" : "Start"
    }

    /// Formatted display label for the current preset (e.g. "10m" or "1h 30m")
    var presetDisplayLabel: String {
        DurationParser.displayString(for: presetSeconds)
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        guard isRunning, let endDate else {
            return remainingSeconds
        }
        return max(Int(ceil(endDate.timeIntervalSince(date))), 0)
    }

    func remainingText(at date: Date = .now) -> String {
        let total = remainingSeconds(at: date)
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            let m = total / 60
            let s = total % 60
            return String(format: "%02d:%02d", m, s)
        }
    }

    /// Select by total seconds
    func selectPreset(_ seconds: Int) {
        let clamped = max(1, min(seconds, 7 * 86400)) // max 7 days
        guard presetSeconds != clamped else { return }

        recordCurrentProgressIfNeeded(referenceDate: .now)
        completionTask?.cancel()
        completionTask = nil
        endDate = nil
        isRunning = false
        hasActiveSession = false
        presetSeconds = clamped
        remainingSeconds = clamped
        recordedSecondsForCurrentSession = 0
    }

    /// Parse a free-form string (e.g. "10m", "1h30m", "90") and apply it
    /// Returns `true` if parsing succeeded.
    @discardableResult
    func setDuration(from text: String) -> Bool {
        guard let seconds = DurationParser.parse(text) else { return false }
        selectPreset(seconds)
        return true
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }

        if !hasActiveSession {
            recordedSecondsForCurrentSession = 0
        }
        hasActiveSession = true
        isRunning = true
        endDate = .now.addingTimeInterval(TimeInterval(remainingSeconds))
        startCompletionTask()
    }

    func pause() {
        guard isRunning else { return }

        recordCurrentProgressIfNeeded(referenceDate: .now)
        remainingSeconds = remainingSeconds(at: .now)
        isRunning = false
        endDate = nil
        completionTask?.cancel()
        completionTask = nil
    }

    func reset() {
        recordCurrentProgressIfNeeded(referenceDate: .now)
        completionTask?.cancel()
        completionTask = nil
        endDate = nil
        isRunning = false
        hasActiveSession = false
        remainingSeconds = presetSeconds
        recordedSecondsForCurrentSession = 0
    }

    func shutdown() {
        recordCurrentProgressIfNeeded(referenceDate: .now)
        completionTask?.cancel()
        completionTask = nil
    }

    private func startCompletionTask() {
        completionTask?.cancel()

        let duration = remainingSeconds(at: .now)
        completionTask = Task { @MainActor [weak self] in
            guard let self, duration > 0 else { return }

            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self.isRunning else { return }

            self.recordCurrentProgressIfNeeded(referenceDate: .now)
            AppNotificationManager.sendNotification(title: "Countdown Complete", body: "Your timer has finished.")
            // Auto-reset back to preset duration
            self.completionTask = nil
            self.endDate = nil
            self.isRunning = false
            self.hasActiveSession = false
            self.recordedSecondsForCurrentSession = 0
            self.remainingSeconds = self.presetSeconds
        }
    }

    private func recordCurrentProgressIfNeeded(referenceDate: Date) {
        let elapsedSeconds = max(presetSeconds - remainingSeconds(at: referenceDate), 0)
        let delta = elapsedSeconds - recordedSecondsForCurrentSession
        guard delta > 0 else { return }

        learningStatsStore.record(seconds: delta, source: .countdown)
        recordedSecondsForCurrentSession += delta
    }
}
