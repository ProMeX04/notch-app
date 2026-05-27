import AppKit
import Foundation
import NotchFocusFeature

@MainActor
private struct NotchPomodoroSoundPlayer: PomodoroSoundPlaying {
    func playNotification() {
        SoundManager.playNotification()
    }

    func playFocusComplete() {
        SoundManager.playFocusComplete()
    }

    func playBreakComplete() {
        SoundManager.playBreakComplete()
    }
}

@MainActor
private struct NotchPomodoroNotificationPoster: PomodoroNotificationPosting {
    func postPhaseStarted(phase: PomodoroPhase, reminder: MotivationalQuote, language: String) {
        let title = Localization.get(phase.rawValue, lang: language)
        var body = reminder.text
        if !reminder.author.isEmpty {
            body += "\n" + reminder.author
        }

        AppNotificationManager.sendNotification(
            title: title,
            body: body,
            identifier: "notch.pomodoro.phase-start.\(UUID().uuidString)"
        )
    }
}

@MainActor
final class FocusStatsRecorder: LearningStatsRecording {
    private let localStats: LearningStatsStore
    private let dailyStats: FocusDailyStatsRepository

    init(localStats: LearningStatsStore, dailyStats: FocusDailyStatsRepository) {
        self.localStats = localStats
        self.dailyStats = dailyStats
    }

    func recordFocusedInterval(_ interval: DateInterval, source: LearningActivitySource) {
        localStats.recordFocusedInterval(interval, source: source)
        if source == .pomodoro {
            dailyStats.recordFocusedInterval(interval)
        }
    }

    func recordCompletedFocusSession(at date: Date, source: LearningActivitySource) {
        localStats.recordCompletedFocusSession(at: date, source: source)
        if source == .pomodoro {
            dailyStats.recordCompletedFocusSession(at: date)
        }
    }
}

extension PomodoroViewModel {
    convenience init(
        userDefaults: UserDefaults = .standard,
        stateRepository: PomodoroStateRepository = PomodoroStateRepository(),
        learningStatsRecorder: LearningStatsRecording
    ) {
        self.init(
            userDefaults: userDefaults,
            stateRepository: stateRepository,
            learningStatsRecorder: learningStatsRecorder,
            appLanguageProvider: AppLanguageProvider(userDefaults: userDefaults),
            soundPlayer: NotchPomodoroSoundPlayer(),
            notificationPoster: NotchPomodoroNotificationPoster(),
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            nowProvider: { .now },
            sleepHandler: { duration in
                try await Task.sleep(for: .seconds(duration))
            }
        )
    }
}
