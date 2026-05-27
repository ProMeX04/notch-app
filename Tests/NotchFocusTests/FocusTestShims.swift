import AppKit
import Foundation
import NotchFocusFeature

struct Localization {
    static func get(_ key: String, lang: String) -> String {
        key
    }
}

@MainActor
struct SoundManager {
    static func playFocusComplete() {}
    static func playBreakComplete() {}
    static func playNotification() {}
}

struct AppNotificationManager {
    static func sendNotification(title: String, body: String, identifier: String = UUID().uuidString) {}
}

@MainActor
struct TestPomodoroSoundPlayer: PomodoroSoundPlaying {
    func playNotification() {}
    func playFocusComplete() {}
    func playBreakComplete() {}
}

@MainActor
struct TestPomodoroNotificationPoster: PomodoroNotificationPosting {
    func postPhaseStarted(phase: PomodoroPhase, reminder: MotivationalQuote, language: String) {}
}

@MainActor
final class TestLearningStatsRecorder: LearningStatsRecording {
    private(set) var intervals: [(interval: DateInterval, source: LearningActivitySource)] = []
    private(set) var completedSessions: [(date: Date, source: LearningActivitySource)] = []

    func recordFocusedInterval(_ interval: DateInterval, source: LearningActivitySource) {
        intervals.append((interval, source))
    }

    func recordCompletedFocusSession(at date: Date, source: LearningActivitySource) {
        completedSessions.append((date, source))
    }
}
