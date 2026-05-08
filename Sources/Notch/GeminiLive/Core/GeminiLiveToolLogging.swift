import Foundation

enum GeminiLiveToolLogging {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Gemini tools] \(message())")
        #endif
    }
}
