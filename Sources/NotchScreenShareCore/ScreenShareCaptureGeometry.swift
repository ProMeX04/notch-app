import CoreGraphics

public struct ScreenShareDisplayDescriptor: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(id: UInt32, frame: CGRect, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.frame = frame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct ScreenShareCapturePlan: Equatable, Sendable {
    public let displayID: UInt32
    public let displayFrame: CGRect
    public let screenRect: CGRect
    public let sourceRect: CGRect
    public let outputWidth: Int
    public let outputHeight: Int

    public init(
        displayID: UInt32,
        displayFrame: CGRect,
        screenRect: CGRect,
        sourceRect: CGRect,
        outputWidth: Int,
        outputHeight: Int
    ) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.screenRect = screenRect
        self.sourceRect = sourceRect
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
    }
}

public enum ScreenShareCaptureGeometry {
    public static func resolveCapturePlan(
        requestedRect: CGRect,
        displays: [ScreenShareDisplayDescriptor]
    ) -> ScreenShareCapturePlan? {
        let requestedRect = requestedRect.standardized
        guard requestedRect.width > 0, requestedRect.height > 0 else { return nil }

        guard let display = displays.max(by: {
            intersectionArea($0.frame, requestedRect) < intersectionArea($1.frame, requestedRect)
        }) else { return nil }

        let displayFrame = display.frame.standardized
        let screenRect = requestedRect.intersection(displayFrame).standardized
        guard !screenRect.isNull, screenRect.width > 0, screenRect.height > 0 else { return nil }

        let sourceRect = CGRect(
            x: screenRect.minX - displayFrame.minX,
            y: displayFrame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        ).standardized
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }

        let scaleX = CGFloat(display.pixelWidth) / max(displayFrame.width, 1)
        let scaleY = CGFloat(display.pixelHeight) / max(displayFrame.height, 1)
        let outputWidth = max(Int((sourceRect.width * scaleX).rounded(.up)), 1)
        let outputHeight = max(Int((sourceRect.height * scaleY).rounded(.up)), 1)

        return ScreenShareCapturePlan(
            displayID: display.id,
            displayFrame: displayFrame,
            screenRect: screenRect,
            sourceRect: sourceRect,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
