import AppKit
import Foundation

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
