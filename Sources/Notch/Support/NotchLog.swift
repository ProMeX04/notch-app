import os.log

enum NotchLog {
    static let app = Logger(subsystem: "dev.notch", category: "App")
    static let notification = Logger(subsystem: "dev.notch", category: "Notification")
    static let mediaRemote = Logger(subsystem: "dev.notch", category: "MediaRemote")
    static let geminiLive = Logger(subsystem: "dev.notch", category: "GeminiLive")
}
