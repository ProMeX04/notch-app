import AppKit
import Foundation
import NotchFocusCore

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
    private(set) var recordedEvents: [(seconds: Int, source: LearningActivitySource)] = []

    func record(seconds: Int, source: LearningActivitySource) {
        recordedEvents.append((seconds, source))
    }
}
