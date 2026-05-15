import AppKit
import Combine
import SwiftUI

@MainActor
protocol AgentResultsWindowControlling: AnyObject {
    func observeStore()
    func hide()
}

@MainActor
final class AgentResultsWindowController: AgentResultsWindowControlling {
    static let shared = AgentResultsWindowController(store: .shared)

    private let store: AgentResultStore
    private var window: NSPanel?
    private var hostingController: NSHostingController<AgentResultsView>?
    private var cancellables = Set<AnyCancellable>()
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var lastObservedBatchCount = 0
    private var hasSubscribed = false
    private var pendingContentFit = false
    private var lastMeasuredContentSize: CGSize = .zero

    private let panelWidth: CGFloat = 400
    private let panelHeight: CGFloat = 360
    private let frameDefaultsKey = "dev.notch.agent-results.frame"

    private init(store: AgentResultStore) {
        self.store = store
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// Boot subscription so the panel auto-flashes / opens on new batches.
    /// Safe to call multiple times.
    func observeStore() {
        guard !hasSubscribed else { return }
        hasSubscribed = true

        lastObservedBatchCount = store.batchAppendCount

        store.$batchAppendCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                guard let self else { return }
                guard newCount > self.lastObservedBatchCount else {
                    self.lastObservedBatchCount = newCount
                    return
                }
                self.lastObservedBatchCount = newCount
                self.pendingContentFit = true
                self.show()
                self.flashOnNewBatch()
            }
            .store(in: &cancellables)

        store.$showingHistory
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.pendingContentFit = true
                self.fitToMeasuredContentIfNeeded()
            }
            .store(in: &cancellables)
    }

    func show() {
        let panel = ensureWindow()
        panel.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func flashOnNewBatch() {
        guard let window else { return }
        // Subtle alpha pulse to draw attention without yanking focus.
        let originalAlpha = window.alphaValue
        let pulse = CAKeyframeAnimation(keyPath: "alphaValue")
        pulse.values = [originalAlpha, max(0.4, originalAlpha * 0.55), originalAlpha]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.duration = 0.45
        window.animations = ["alphaValue": pulse]
        window.animator().alphaValue = originalAlpha
    }

    // MARK: - Window setup

    private func ensureWindow() -> NSPanel {
        if let window {
            // Refresh the SwiftUI root in case the singleton store was swapped.
            hostingController?.rootView = makeRootView()
            return window
        }

        let initialFrame = loadSavedFrame() ?? defaultFrame()
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = NotchHUDWindowLevels.aboveOrb
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = NSSize(width: 160, height: 120)

        let hosting = NSHostingController(rootView: makeRootView())
        panel.contentViewController = hosting

        let trackedWindowNumber = panel.windowNumber
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let window = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self?.saveFrame(window.frame)
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let window = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self?.saveFrame(window.frame)
            }
        }

        self.window = panel
        self.hostingController = hosting
        return panel
    }

    // MARK: - Frame persistence

    private func defaultFrame() -> CGRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visibleFrame.maxX - panelWidth - 24
        let y = visibleFrame.maxY - panelHeight - 24
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: frameDefaultsKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else {
            return nil
        }
        let frame = CGRect(x: x, y: y, width: w, height: h)
        return clampToVisibleScreens(frame)
    }

    private func saveFrame(_ frame: CGRect) {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height],
            forKey: frameDefaultsKey
        )
    }

    private func clampToVisibleScreens(_ frame: CGRect) -> CGRect {
        let minOverlap: CGFloat = 60
        let intersects = NSScreen.screens.contains { screen in
            let inter = frame.intersection(screen.visibleFrame)
            return inter.width >= minOverlap && inter.height >= minOverlap
        }
        if intersects { return frame }
        return defaultFrame()
    }

    private func makeRootView() -> AgentResultsView {
        AgentResultsView(store: store) { [weak self] size in
            Task { @MainActor [weak self] in
                self?.contentSizeDidChange(size)
            }
        }
    }

    private func contentSizeDidChange(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastMeasuredContentSize = size
        fitToMeasuredContentIfNeeded()
    }

    private func fitToMeasuredContentIfNeeded() {
        guard pendingContentFit, lastMeasuredContentSize != .zero else { return }
        guard let window else { return }
        pendingContentFit = false

        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let currentFrame = window.frame
        let maxWidth = min(640, visibleFrame.width - 48)
        let maxHeight = min(720, visibleFrame.height - 48)
        let desiredWidth = min(max(currentFrame.width, 360), maxWidth)
        let desiredHeight = min(max(lastMeasuredContentSize.height + 12, 120), maxHeight)

        let newFrame = CGRect(
            x: min(max(currentFrame.maxX - desiredWidth, visibleFrame.minX + 12), visibleFrame.maxX - desiredWidth - 12),
            y: min(max(currentFrame.maxY - desiredHeight, visibleFrame.minY + 12), visibleFrame.maxY - desiredHeight - 12),
            width: desiredWidth,
            height: desiredHeight
        )

        guard abs(newFrame.width - currentFrame.width) > 1 || abs(newFrame.height - currentFrame.height) > 1 else {
            return
        }
        window.setFrame(newFrame, display: true, animate: true)
        saveFrame(newFrame)
    }

}
