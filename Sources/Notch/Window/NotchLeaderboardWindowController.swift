import AppKit
import SwiftUI
import Combine

private final class NotchLeaderboardKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NotchLeaderboardHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchLeaderboardWindowController {
    private var panel: NSPanel?
    private var hostingView: NotchLeaderboardHostingView<FocusLeaderboardPanelContentView>?
    private var cancellables = Set<AnyCancellable>()
    private var moveObserver: NSObjectProtocol?
    private weak var preferredScreen: NSScreen?
    private weak var focusCloudSync: FocusCloudSyncCoordinator?

    private let panelWidth: CGFloat = 360
    private let panelHeight: CGFloat = 480
    private let defaultsKey = "dev.notch.leaderboard-panel.frame"

    init() {
        NotificationCenter.default.publisher(for: Notification.Name("ToggleLeaderboardPanel"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggle()
            }
            .store(in: &cancellables)
    }

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel, hostingView != nil else { return }
        if !frameIntersectsAnyVisibleWorkspace(panel.frame) {
            let sc = screenForPlacement()
            let target = clampFrame(panel.frame, to: sc)
            panel.setFrame(target, display: true)
            hostingView?.frame = CGRect(origin: .zero, size: target.size)
        }
    }

    func observe(focusCloudSync: FocusCloudSyncCoordinator) {
        self.focusCloudSync = focusCloudSync
    }

    func toggle() {
        guard let panel, panel.isVisible else {
            show()
            return
        }
        hide()
    }

    func show() {
        guard let focusCloudSync else { return }
        ensurePanel(focusCloudSync: focusCloudSync)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func stopObserving() {
        focusCloudSync = nil
        cancellables.removeAll()
        removeMoveObserver()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Private

    private func screenForPlacement() -> NSScreen {
        preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func defaultFrame(on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let x = vf.maxX - panelWidth - 40
        let y = vf.maxY - panelHeight - 80
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveFrame(_ frame: CGRect) {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height],
            forKey: defaultsKey
        )
    }

    private func dominantScreen(forWindowFrame windowFrame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.frame)
            let area = max(0, inter.width) * max(0, inter.height)
            if area > bestArea {
                bestArea = area
                best = s
            }
        }
        return best
    }

    private func clampFrame(_ frame: CGRect, to screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var f = frame
        let minVisible: CGFloat = 48
        f.origin.x = min(max(f.origin.x, vf.minX - f.width + minVisible), vf.maxX - minVisible)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - minVisible)
        return f
    }

    private func frameIntersectsAnyVisibleWorkspace(_ windowFrame: CGRect) -> Bool {
        let minOverlap: CGFloat = 32
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.visibleFrame)
            if inter.width >= minOverlap, inter.height >= minOverlap {
                return true
            }
        }
        return false
    }

    private func removeMoveObserver() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
    }

    private func ensurePanel(focusCloudSync: FocusCloudSyncCoordinator) {
        let sc = screenForPlacement()

        if let hv = hostingView {
            hv.rootView = FocusLeaderboardPanelContentView(focusCloudSync: focusCloudSync, onClose: { [weak self] in self?.hide() })
            return
        }

        let saved = loadSavedFrame()
        let initial: CGRect
        if let saved {
            let onScreen = dominantScreen(forWindowFrame: saved) ?? sc
            var correctedFrame = saved
            if abs(saved.width - panelWidth) > 5.0 || abs(saved.height - panelHeight) > 5.0 {
                correctedFrame = CGRect(x: saved.origin.x, y: saved.origin.y, width: panelWidth, height: panelHeight)
            }
            initial = clampFrame(correctedFrame, to: onScreen)
        } else {
            initial = defaultFrame(on: sc)
        }

        let panel = NotchLeaderboardKeyPanel(
            contentRect: initial,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        let root = FocusLeaderboardPanelContentView(focusCloudSync: focusCloudSync, onClose: { [weak self] in self?.hide() })
        let hv = NotchLeaderboardHostingView(rootView: root)
        hv.frame = CGRect(origin: .zero, size: initial.size)
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        let trackedWindowNumber = panel.windowNumber
        removeMoveObserver()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let w = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self.saveFrame(w.frame)
            }
        }
    }
}
