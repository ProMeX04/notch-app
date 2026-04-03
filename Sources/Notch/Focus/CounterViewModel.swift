import Foundation

@MainActor
final class CounterViewModel: ObservableObject {
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isRunning = false
    @Published private(set) var hasActiveSession = false

    private var timerTask: Task<Void, Never>?
    private var startDate: Date?
    private var accumulatedSeconds: Int = 0
    private let learningStatsStore: LearningStatsStore
    private var recordedElapsedSecondsForCurrentSession = 0

    init(learningStatsStore: LearningStatsStore) {
        self.learningStatsStore = learningStatsStore
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

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard isRunning, let startDate else {
            return elapsedSeconds
        }
        return accumulatedSeconds + Int(date.timeIntervalSince(startDate))
    }

    func elapsedText(at date: Date = .now) -> String {
        let total = elapsedSeconds(at: date)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }

        if !hasActiveSession {
            recordedElapsedSecondsForCurrentSession = 0
        }
        hasActiveSession = true
        isRunning = true
        startDate = .now
        startTimerTask()
    }

    func pause() {
        guard isRunning else { return }

        recordCurrentProgressIfNeeded(referenceDate: .now)
        accumulatedSeconds = elapsedSeconds(at: .now)
        elapsedSeconds = accumulatedSeconds
        isRunning = false
        startDate = nil
        timerTask?.cancel()
        timerTask = nil
    }

    func reset() {
        recordCurrentProgressIfNeeded(referenceDate: .now)
        timerTask?.cancel()
        timerTask = nil
        startDate = nil
        isRunning = false
        hasActiveSession = false
        accumulatedSeconds = 0
        elapsedSeconds = 0
        recordedElapsedSecondsForCurrentSession = 0
    }

    func shutdown() {
        recordCurrentProgressIfNeeded(referenceDate: .now)
        timerTask?.cancel()
        timerTask = nil
    }

    private func startTimerTask() {
        timerTask?.cancel()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                self.elapsedSeconds = self.elapsedSeconds(at: .now)
            }
        }
    }

    private func recordCurrentProgressIfNeeded(referenceDate: Date) {
        let elapsed = elapsedSeconds(at: referenceDate)
        let delta = elapsed - recordedElapsedSecondsForCurrentSession
        guard delta > 0 else { return }

        learningStatsStore.record(seconds: delta, source: .stopwatch)
        recordedElapsedSecondsForCurrentSession += delta
    }
}
