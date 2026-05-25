public enum ScreenShareMediaResolution: Sendable {
    case low
    case medium
    case high
}

public enum ScreenShareVisualSource: Sendable {
    case camera
    case screen
}

public struct ScreenShareVisualProfile: Equatable, Sendable {
    public let maximumLongEdge: Int?

    public init(maximumLongEdge: Int?) {
        self.maximumLongEdge = maximumLongEdge
    }

    public static func profile(
        source: ScreenShareVisualSource,
        resolution: ScreenShareMediaResolution
    ) -> ScreenShareVisualProfile {
        switch (source, resolution) {
        case (.camera, .low):
            return ScreenShareVisualProfile(maximumLongEdge: 512)
        case (.camera, .medium):
            return ScreenShareVisualProfile(maximumLongEdge: 768)
        case (.camera, .high):
            return ScreenShareVisualProfile(maximumLongEdge: 1280)
        case (.screen, .low):
            return ScreenShareVisualProfile(maximumLongEdge: 768)
        case (.screen, .medium):
            return ScreenShareVisualProfile(maximumLongEdge: 1280)
        case (.screen, .high):
            return ScreenShareVisualProfile(maximumLongEdge: nil)
        }
    }

    public func fittedPixelSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let width = max(width, 1)
        let height = max(height, 1)
        guard let maximumLongEdge, max(width, height) > maximumLongEdge else {
            return (width, height)
        }
        let scale = Double(maximumLongEdge) / Double(max(width, height))
        return (
            max(Int((Double(width) * scale).rounded()), 1),
            max(Int((Double(height) * scale).rounded()), 1)
        )
    }
}
