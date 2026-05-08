import os.log

enum NotchLog {
    static let app = Logger(subsystem: "dev.notch", category: "App")
    static let gemini = Logger(subsystem: "dev.notch", category: "GeminiLive")
    static let notification = Logger(subsystem: "dev.notch", category: "Notification")
    static let mediaRemote = Logger(subsystem: "dev.notch", category: "MediaRemote")
}
