import AppKit
import Foundation
import NotchFocusCore

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

extension PomodoroViewModel {
    convenience init(
        userDefaults: UserDefaults = .standard,
        learningStatsStore: LearningStatsStore
    ) {
        self.init(
            userDefaults: userDefaults,
            learningStatsRecorder: learningStatsStore,
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
