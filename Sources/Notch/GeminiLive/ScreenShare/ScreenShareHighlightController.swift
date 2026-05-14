import AppKit

@MainActor
final class ScreenShareHighlightController {
    private let borderWindow = ScreenShareBorderWindow()
    private let handleWindow = ScreenShareMoveHandleWindow()
    private var contentRect: CGRect = .zero
    private var dragStartRect: CGRect?

    var onRectChanged: ((CGRect) -> Void)?

    init() {
        handleWindow.onDragBegan = { [weak self] in
            guard let self else { return }
            self.dragStartRect = self.contentRect
        }
        handleWindow.onDragChanged = { [weak self] delta in
            self?.moveOverlay(byTotalDelta: delta)
        }
        handleWindow.onDragEnded = { [weak self] in
            self?.dragStartRect = nil
        }
    }

    func show(rect: CGRect) {
        let standardizedRect = rect.standardized.integral
        guard standardizedRect.width >= 2, standardizedRect.height >= 2 else {
            hide()
            return
        }

        if dragStartRect == nil {
            contentRect = standardizedRect
        }
        syncWindows()
        borderWindow.orderFrontRegardless()
        handleWindow.orderFrontRegardless()
    }

    func hide() {
        borderWindow.orderOut(nil)
        handleWindow.orderOut(nil)
    }

    private func moveOverlay(byTotalDelta delta: CGPoint) {
        guard let dragStartRect else { return }
        contentRect = dragStartRect.offsetBy(dx: delta.x, dy: delta.y).integral
        syncWindows()
        onRectChanged?(contentRect)
    }

    private func syncWindows() {
        let borderFrame = contentRect.insetBy(dx: -2, dy: -2)
        borderWindow.setFrame(borderFrame, display: true)
        handleWindow.setFrame(handleFrame(for: borderFrame), display: true)
    }

    private func handleFrame(for frame: CGRect) -> CGRect {
        let size: CGFloat = 18
        let offset: CGFloat = 7
        return CGRect(
            x: frame.maxX - size / 2 + offset,
            y: frame.maxY - size / 2 + offset,
            width: size,
            height: size
        ).integral
    }
}

private final class ScreenShareBorderWindow: NSWindow {
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
        contentView = ScreenShareBorderView(frame: .zero)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenShareMoveHandleWindow: NSWindow {
    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    private var dragStartScreenPoint: CGPoint?

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
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = ScreenShareMoveHandleView(frame: .zero)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = screenPoint(for: event)
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = screenPoint(for: event)
        guard let dragStartScreenPoint else {
            self.dragStartScreenPoint = currentPoint
            onDragBegan?()
            return
        }

        onDragChanged?(CGPoint(
            x: currentPoint.x - dragStartScreenPoint.x,
            y: currentPoint.y - dragStartScreenPoint.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        onDragEnded?()
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        CGPoint(
            x: frame.minX + event.locationInWindow.x,
            y: frame.minY + event.locationInWindow.y
        )
    }
}

private final class ScreenShareBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.systemBlue.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
}

private final class ScreenShareMoveHandleView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        NSColor.systemBlue.withAlphaComponent(0.94).setFill()
        NSBezierPath(ovalIn: bounds).fill()

        NSColor.white.withAlphaComponent(0.85).setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 3.5, dy: 3.5))
        ring.lineWidth = 1.2
        ring.stroke()
    }
}
