import Foundation

package enum LearningActivitySource: String, Codable, CaseIterable {
    case pomodoro

    package var title: String {
        "Pomodoro"
    }
}

@MainActor
package protocol LearningStatsRecording: AnyObject {
    func record(seconds: Int, source: LearningActivitySource)
}

@MainActor
package protocol PomodoroSoundPlaying {
    func playNotification()
    func playFocusComplete()
    func playBreakComplete()
}

@MainActor
package protocol PomodoroNotificationPosting {
    func postPhaseStarted(phase: PomodoroPhase, reminder: MotivationalQuote, language: String)
}

@MainActor
package struct NoopPomodoroSoundPlayer: PomodoroSoundPlaying {
    package init() {}
    package func playNotification() {}
    package func playFocusComplete() {}
    package func playBreakComplete() {}
}

@MainActor
package struct NoopPomodoroNotificationPoster: PomodoroNotificationPosting {
    package init() {}
    package func postPhaseStarted(phase: PomodoroPhase, reminder: MotivationalQuote, language: String) {}
}
