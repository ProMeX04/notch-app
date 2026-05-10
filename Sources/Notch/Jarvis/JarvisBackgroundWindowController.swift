import AppKit

@MainActor
private enum JarvisOrbDockActivation {
    static func syncDockForOrbDisplayedOnScreen(_ displayed: Bool) {
        let prefersDockWhileOrb = JarvisTalkBackgroundOrbSettings.prefersDockIconWhileOrbShown
        let shouldUseRegularDock = displayed && prefersDockWhileOrb

        let target: NSApplication.ActivationPolicy = shouldUseRegularDock ? .regular : .accessory
        guard NSApp.activationPolicy() != target else { return }

        if !NSApp.setActivationPolicy(target) {
            NotchLog.app.error("JarvisOrbDockActivation.setActivationPolicy failed for \(shouldUseRegularDock ? ".regular" : ".accessory")")
        }
    }
}

/// Native fullscreen đưa window sang Space riêng, dễ làm orb "biến mất" khi app khác mở.
/// Panel này thay bằng fullscreen nội bộ: lưu frame cũ rồi phủ màn trong Space hiện tại.
private final class JarvisOrbPanel: NSPanel {
    var onPseudoFullScreenChanged: ((Bool) -> Void)?

    private var frameBeforePseudoFullScreen: NSRect?

    var isPseudoFullScreen: Bool {
        frameBeforePseudoFullScreen != nil
    }

    override func toggleFullScreen(_ sender: Any?) {
        if let previousFrame = frameBeforePseudoFullScreen {
            frameBeforePseudoFullScreen = nil
            setFrame(previousFrame, display: true, animate: true)
            onPseudoFullScreenChanged?(false)
            return
        }

        frameBeforePseudoFullScreen = frame
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let targetFrame = targetScreen?.frame ?? frame
        setFrame(targetFrame, display: true, animate: true)
        onPseudoFullScreenChanged?(true)
    }
}

/// Điều khiển cửa sổ nổi hiển thị orb Gemini Live — resize cạnh + pseudo-fullscreen trong Space hiện tại.
@MainActor
final class JarvisBackgroundWindowController {
    static let shared = JarvisBackgroundWindowController()

    private static let minimumOrbWindowSize = NSSize(width: 260, height: 300)
    private static let defaultOrbWindowSize = NSSize(width: 468, height: 520)
    /// Đủ lớn cho màn retina; không cần vô cực thật để tránh lỗi layout.
    private static let relaxedMaximumOrbWindowSize = NSSize(width: 8192, height: 8192)

    private static let savedFrameDefaultsKey = "jarvisTalkOrbFloatingWindowFrame"

    private var orbPanel: JarvisOrbPanel?
    private var orbContentView: JarvisBackgroundView?
    private var windowObservers: [NSObjectProtocol] = []

    private var currentEnergyState: JarvisEnergyState = .idle
    private var currentSignalLevel = 0.0

    var isVisible: Bool {
        orbPanel?.isVisible == true
    }

    private init() {}

    func show() {
        if orbPanel == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }

            let frame = Self.resolveInitialFrame(referenceScreen: screen)
            let panel = Self.makeOrbPanel(screen: screen)
            panel.onPseudoFullScreenChanged = { [weak self, weak panel] isFullScreen in
                guard let panel else { return }
                self?.orbFullscreenChanged(panel: panel, isFullScreen: isFullScreen)
            }

            panel.setFrame(frame, display: false)

            let jarvisView = JarvisBackgroundView(frame: NSRect(origin: .zero, size: frame.size))

            jarvisView.autoresizingMask = [.width, .height]
            jarvisView.setEnergyState(currentEnergyState, signalLevel: currentSignalLevel)
            jarvisView.wantsLayer = true
            applyOrbCornerStyle(panel: panel, rounded: true)

            orbContentView = jarvisView

            let controller = NSViewController()
            controller.view = jarvisView

            panel.contentViewController = controller
            orbPanel = panel

            observeWindow(panel)
        }

        guard let panel = orbPanel else { return }
        refreshOrbPresentationForActiveOrbWindow()
        panel.orderFrontRegardless()
    }

    func hide() {
        tearDownWindowObservers()
        if let orbPanel {
            orbPanel.orderOut(nil)
            orbPanel.contentViewController = nil
        }
        orbPanel = nil
        orbContentView = nil

        JarvisOrbDockActivation.syncDockForOrbDisplayedOnScreen(false)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func reposition() {
        guard let panel = orbPanel else { return }
        if panel.jarvisOrbIsPseudoFullScreen { return }

        let next = Self.clampFrameIfNeeded(panel.frame)
        let before = RectSnapshot(panel.frame)
        let after = RectSnapshot(next)
        guard before != after else { return }

        panel.setFrame(next, display: true)
        Self.saveFrame(panel.frame)
    }

    func reloadOrbEmbeddedWebIfStoredPresetChanged() {
        orbContentView?.reloadOrbEmbeddedWebIfStoredPresetChanged()
    }

    func setEnergyState(_ state: JarvisEnergyState, signalLevel: Double = 0) {
        currentEnergyState = state
        currentSignalLevel = signalLevel
        orbContentView?.setEnergyState(state, signalLevel: signalLevel)
    }

    /// Khi có cửa sổ orb, áp dụng Dock + stacking level theo defaults (được gọi lại sau mỗi lần `UserDefaults.didChange`).
    private func refreshOrbPresentationForActiveOrbWindow() {
        guard let panel = orbPanel else { return }
        panel.level = JarvisTalkBackgroundOrbSettings.prefersOrbAboveNormalWindows
            ? NotchHUDWindowLevels.orbOverExternalAppsBelowNotchFloaterTier
            : .normal
        JarvisOrbDockActivation.syncDockForOrbDisplayedOnScreen(true)
    }

    private func observeWindow(_ panel: NSPanel) {
        tearDownWindowObservers()

        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { notification in
            guard let panel = notification.object as? NSPanel else { return }
            MainActor.assumeIsolated {
                guard !panel.jarvisOrbIsPseudoFullScreen else { return }
                Self.saveFrame(panel.frame)
            }
        })

        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { notification in
            guard let panel = notification.object as? NSPanel else { return }
            MainActor.assumeIsolated {
                guard !panel.jarvisOrbIsPseudoFullScreen else { return }
                Self.saveFrame(panel.frame)
            }
        })
    }

    private func orbFullscreenChanged(panel: NSPanel, isFullScreen: Bool) {
        guard orbPanel === panel else { return }
        applyOrbCornerStyle(panel: panel, rounded: !isFullScreen)
        Self.saveFrame(panel.frame)
    }

    private func tearDownWindowObservers() {
        for token in windowObservers {
            NotificationCenter.default.removeObserver(token)
        }
        windowObservers.removeAll()
    }

    private func applyOrbCornerStyle(panel: NSWindow?, rounded: Bool) {
        orbContentView?.layer?.cornerRadius = rounded ? 20 : 0
        orbContentView?.layer?.masksToBounds = true
        panel?.invalidateShadow()
    }

    private static func makeOrbPanel(screen: NSScreen) -> JarvisOrbPanel {
        let panel = JarvisOrbPanel(
            contentRect: CGRect(origin: .zero, size: defaultOrbWindowSize),
            styleMask: [.titled, .resizable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.title = ""
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        if #available(macOS 11.0, *) {
            panel.titlebarSeparatorStyle = .none
        }

        for kind in [
            NSWindow.ButtonType.closeButton,
            NSWindow.ButtonType.miniaturizeButton,
            NSWindow.ButtonType.zoomButton,
        ] {
            panel.standardWindowButton(kind)?.isHidden = true
        }

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        panel.level = NotchHUDWindowLevels.orbOverExternalAppsBelowNotchFloaterTier
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
        ]

        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true

        panel.isReleasedWhenClosed = false
        panel.minSize = minimumOrbWindowSize
        panel.maxSize = relaxedMaximumOrbWindowSize

        panel.invalidateShadow()

        return panel
    }

    private static func resolveInitialFrame(referenceScreen screen: NSScreen) -> CGRect {
        if let saved = loadSavedFrame() {
            let candidate = CGRect(origin: saved.origin, size: clipWindowSize(saved.size))
            if overlapsVisibleEnough(candidate) {
                return candidate
            }
        }
        let size = defaultOrbWindowSize
        return center(of: size, inside: screen.visibleFrame)
    }

    private static func center(of size: CGSize, inside visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func clipWindowSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumOrbWindowSize.width), relaxedMaximumOrbWindowSize.width),
            height: min(max(size.height, minimumOrbWindowSize.height), relaxedMaximumOrbWindowSize.height)
        )
    }

    private static func overlapsVisibleEnough(_ frame: CGRect) -> Bool {
        let area = frame.width * frame.height
        guard area > 8_000 else { return false }
        var covered: CGFloat = 0
        for screen in NSScreen.screens {
            let inter = frame.intersection(screen.visibleFrame)
            covered = max(covered, inter.width * inter.height)
        }
        return covered >= area * 0.22
    }

    private static func clampFrameIfNeeded(_ frame: CGRect) -> CGRect {
        let size = clipWindowSize(frame.size)
        let rectAt = CGRect(origin: frame.origin, size: size)
        if overlapsVisibleEnough(rectAt) {
            return rectAt
        }
        guard let main = NSScreen.main ?? NSScreen.screens.first else {
            return rectAt
        }
        return center(of: size, inside: main.visibleFrame)
    }

    private static func saveFrame(_ frame: NSRect) {
        let clipped = CGSize(
            width: min(max(frame.size.width, minimumOrbWindowSize.width), relaxedMaximumOrbWindowSize.width),
            height: min(max(frame.size.height, minimumOrbWindowSize.height), relaxedMaximumOrbWindowSize.height)
        )
        UserDefaults.standard.set(
            [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "w": clipped.width,
                "h": clipped.height,
            ],
            forKey: savedFrameDefaultsKey
        )
    }

    private static func CGFloatFromDefaults(_ value: Any?) -> CGFloat? {
        switch value {
        case let v as CGFloat:
            return v
        case let v as Double:
            return CGFloat(v)
        case let v as Float:
            return CGFloat(v)
        case let v as Int:
            return CGFloat(v)
        case let v as NSNumber:
            return CGFloat(truncating: v)
        default:
            return nil
        }
    }

    private static func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: savedFrameDefaultsKey) else {
            return nil
        }

        guard let x = CGFloatFromDefaults(dict["x"]),
              let y = CGFloatFromDefaults(dict["y"]) else {
            return nil
        }

        let wRaw = CGFloatFromDefaults(dict["w"]) ?? defaultOrbWindowSize.width
        let hRaw = CGFloatFromDefaults(dict["h"]) ?? defaultOrbWindowSize.height
        let size = clipWindowSize(CGSize(width: wRaw, height: hRaw))

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

private extension NSWindow {
    var jarvisOrbIsPseudoFullScreen: Bool {
        (self as? JarvisOrbPanel)?.isPseudoFullScreen == true
    }
}

private struct RectSnapshot: Equatable {
    let ox: CGFloat
    let oy: CGFloat
    let ow: CGFloat
    let oh: CGFloat

    init(_ r: CGRect) {
        ox = r.origin.x
        oy = r.origin.y
        ow = r.size.width
        oh = r.size.height
    }
}
