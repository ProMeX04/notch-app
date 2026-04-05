import AppKit

@MainActor
final class ScreenShareHighlightController {
    private let overlayWindow: ScreenShareHighlightWindow

    init() {
        overlayWindow = ScreenShareHighlightWindow()
    }

    func show(rect: CGRect) {
        let standardizedRect = rect.standardized.integral
        guard standardizedRect.width >= 2, standardizedRect.height >= 2 else {
            hide()
            return
        }

        overlayWindow.setFrame(standardizedRect.insetBy(dx: -2, dy: -2), display: true)
        overlayWindow.orderFrontRegardless()
    }

    func hide() {
        overlayWindow.orderOut(nil)
    }
}

private final class ScreenShareHighlightWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = ScreenShareHighlightView(frame: .zero)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenShareHighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let outerPath = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.systemBlue.withAlphaComponent(0.92).setStroke()
        outerPath.lineWidth = 3
        outerPath.stroke()

        let innerBounds = bounds.insetBy(dx: 4, dy: 4)
        guard innerBounds.width > 0, innerBounds.height > 0 else { return }
        let innerPath = NSBezierPath(roundedRect: innerBounds, xRadius: 11, yRadius: 11)
        NSColor.white.withAlphaComponent(0.55).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
    }
}
