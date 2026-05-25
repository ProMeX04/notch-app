import Foundation

public struct ScreenShareFrameChangeFilter: Sendable {
    private var lastSentFrame: Data?

    public init() {}

    public mutating func shouldSend(_ frame: Data) -> Bool {
        guard lastSentFrame != frame else { return false }
        lastSentFrame = frame
        return true
    }

    public mutating func reset() {
        lastSentFrame = nil
    }
}
