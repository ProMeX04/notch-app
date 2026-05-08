import AppKit

@MainActor
final class ScreenRegionSelectionController {
    private var windows: [ScreenRegionSelectionWindow] = []
    private var completion: ((CGRect?) -> Void)?

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        cancelSelection(notify: false)
        self.completion = completion

        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            let window = ScreenRegionSelectionWindow(screen: screen)
            window.selectionHandler = { [weak self] rect in
                self?.finish(with: rect)
            }
            window.cancelHandler = { [weak self] in
                self?.finish(with: nil)
            }
            window.orderFrontRegardless()
            return window
        }

        windows.first?.makeKeyAndOrderFront(nil)
    }

    func cancelSelection(notify: Bool = true) {
        let completion = notify ? self.completion : nil
        teardown()
        completion?(nil)
    }

    private func finish(with rect: CGRect?) {
        let completion = self.completion
        teardown()
        completion?(rect)
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion = nil
    }
}

private final class ScreenRegionSelectionWindow: NSWindow {
    var selectionHandler: ((CGRect) -> Void)?
    var cancelHandler: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let selectionView = ScreenRegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        selectionView.autoresizingMask = [.width, .height]
        selectionView.selectionHandler = { [weak self, weak selectionView] localRect in
            guard let self, let selectionView else { return }
            let windowRect = selectionView.convert(localRect, to: nil)
            let screenRect = self.convertToScreen(windowRect).standardized
            self.selectionHandler?(screenRect)
        }
        selectionView.cancelHandler = { [weak self] in
            self?.cancelHandler?()
        }
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ScreenRegionSelectionView: NSView {
    var selectionHandler: ((CGRect) -> Void)?
    var cancelHandler: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = selectionRect(minimumSize: 12) else {
            cancelHandler?()
            return
        }
        selectionHandler?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelHandler?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        dirtyRect.fill()

        guard let rect = selectionRect(minimumSize: 0) else { return }
        NSGraphicsContext.current?.cgContext.clear(rect)

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill()
    }

    private func selectionRect(minimumSize: CGFloat) -> CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        let rect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).integral

        guard rect.width >= minimumSize, rect.height >= minimumSize else { return nil }
        return rect
    }
}
