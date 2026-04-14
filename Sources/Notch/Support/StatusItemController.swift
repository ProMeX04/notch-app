import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let windowController: NotchWindowController
    private let launchAtLoginController = LaunchAtLoginController()
    private var cancellables = Set<AnyCancellable>()

    private var pomodoroStatusItem: NSStatusItem?
    private var timerTick: Timer?
    private var lastRenderedTimerCacheKey: String?
    private var lastRenderedTimerImage: NSImage?

    private lazy var visibilityItem = NSMenuItem(
        title: "Hide Notch",
        action: #selector(toggleVisibility),
        keyEquivalent: ""
    )

    private lazy var pinItem = NSMenuItem(
        title: "Pin Open",
        action: #selector(togglePinned),
        keyEquivalent: ""
    )

    private lazy var mediaItem = NSMenuItem(
        title: "Open Media",
        action: #selector(showMediaPanel),
        keyEquivalent: ""
    )

    private lazy var pomodoroItem = NSMenuItem(
        title: "Open Focus",
        action: #selector(showPomodoroPanel),
        keyEquivalent: ""
    )

    private lazy var talkItem = NSMenuItem(
        title: "Open Talk",
        action: #selector(showTalkPanel),
        keyEquivalent: ""
    )

    private lazy var shelfItem = NSMenuItem(
        title: "Open Shelf",
        action: #selector(showShelfPanel),
        keyEquivalent: ""
    )

    private lazy var togglePomodoroItem = NSMenuItem(
        title: "Start Focus Timer",
        action: #selector(togglePomodoro),
        keyEquivalent: ""
    )

    private lazy var toggleTalkItem = NSMenuItem(
        title: "Connect Gemini Live",
        action: #selector(toggleTalk),
        keyEquivalent: ""
    )

    private lazy var manageServiceKeysItem = NSMenuItem(
        title: "Manage Keys…",
        action: #selector(showManageKeys),
        keyEquivalent: ""
    )

    private lazy var resetPomodoroItem = NSMenuItem(
        title: "Reset Focus Timer",
        action: #selector(resetPomodoro),
        keyEquivalent: ""
    )

    private lazy var launchAtLoginItem = NSMenuItem(
        title: "Launch At Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    init(windowController: NotchWindowController) {
        self.windowController = windowController
        super.init()

        if let button = statusItem.button {
            button.image = loadStatusBarTemplateImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        menu.delegate = self

        visibilityItem.target = self
        pinItem.target = self
        mediaItem.target = self
        pomodoroItem.target = self
        talkItem.target = self
        shelfItem.target = self
        togglePomodoroItem.target = self
        toggleTalkItem.target = self
        manageServiceKeysItem.target = self
        resetPomodoroItem.target = self
        launchAtLoginItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.items = [
            visibilityItem,
            pinItem,
            .separator(),
            mediaItem,
            shelfItem,
            .separator(),
            talkItem,
            toggleTalkItem,
            manageServiceKeysItem,
            .separator(),
            pomodoroItem,
            togglePomodoroItem,
            resetPomodoroItem,
            .separator(),
            launchAtLoginItem,
            .separator(),
            quitItem,
        ]

        statusItem.menu = menu
        statusItem.isVisible = false

        let pomo = windowController.pomodoroViewModel
        Publishers.CombineLatest(
            pomo.$isRunning,
            pomo.$hasActiveSession
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshAllFocusStatusItems()
        }
        .store(in: &cancellables)

        refreshAllFocusStatusItems()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginController.refreshStatus()
        visibilityItem.title = windowController.isVisible ? "Hide Notch" : "Show Notch"
        pinItem.state = windowController.presentationModel.isPinnedOpen ? .on : .off
        mediaItem.state = windowController.presentationModel.selectedPanel == .media ? .on : .off
        pomodoroItem.state = windowController.presentationModel.selectedPanel == .focus ? .on : .off
        talkItem.state = windowController.presentationModel.selectedPanel == .talk ? .on : .off
        shelfItem.state = windowController.presentationModel.selectedPanel == .shelf ? .on : .off
        launchAtLoginItem.state = launchAtLoginController.isEnabled ? .on : .off

        switch windowController.geminiLiveViewModel.connectionState {
        case .connected, .connecting:
            toggleTalkItem.title = "Disconnect Gemini Live"
        case .disconnected, .failed:
            toggleTalkItem.title = "Connect Gemini Live"
        }
        toggleTalkItem.isEnabled = true

        if windowController.pomodoroViewModel.isRunning {
            togglePomodoroItem.title = "Pause Pomodoro"
        } else if windowController.pomodoroViewModel.hasActiveSession {
            togglePomodoroItem.title = "Resume Pomodoro"
        } else {
            togglePomodoroItem.title = "Start Pomodoro"
        }
        togglePomodoroItem.isEnabled = true

        resetPomodoroItem.title = "Reset Pomodoro"
        resetPomodoroItem.isEnabled = windowController.pomodoroViewModel.hasActiveSession
    }

    @objc
    private func toggleVisibility() {
        windowController.toggleVisibility()
    }

    @objc
    private func togglePinned() {
        windowController.togglePinned()
    }

    @objc
    private func showMediaPanel() {
        windowController.showMediaPanel()
    }

    @objc
    private func showPomodoroPanel() {
        windowController.showFocusPanel()
    }

    @objc
    private func showTalkPanel() {
        windowController.showTalkPanel()
    }

    @objc
    private func showShelfPanel() {
        windowController.showShelfPanel()
    }

    @objc
    private func togglePomodoro() {
        windowController.togglePomodoro()
    }

    @objc
    private func toggleTalk() {
        windowController.toggleGeminiLive()
    }

    @objc
    private func showManageKeys() {
        windowController.presentManageKeysFromStatusMenu()
    }

    @objc
    private func resetPomodoro() {
        windowController.resetPomodoro()
    }

    @objc
    private func toggleLaunchAtLogin() {
        do {
            try launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch At Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func generateTimerImage(symbolName: String, text: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14.5, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = text.size(withAttributes: textAttributes)

        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .bold)
        guard let symbolBase = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }

        let symbolImage = NSImage(size: symbolBase.size, flipped: false) { rect in
            guard symbolBase.size.width > 0 else { return true }
            symbolBase.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        let symbolSize = symbolImage.size
        let paddingX: CGFloat = 10
        let spacing: CGFloat = 5
        let height: CGFloat = 24
        let width = paddingX + symbolSize.width + spacing + textSize.width + paddingX

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            NSColor(white: 0.05, alpha: 1.0).setFill()
            path.fill()

            let symbolRect = NSRect(
                x: paddingX,
                y: (rect.height - symbolSize.height) / 2.0,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbolImage.draw(in: symbolRect)

            let textRect = NSRect(
                x: paddingX + symbolSize.width + spacing,
                y: (rect.height - textSize.height) / 2.0 - 0.5,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: textAttributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func refreshAllFocusStatusItems() {
        updatePomodoroStatusItem()
    }

    private func updatePomodoroStatusItem() {
        let pomodoro = windowController.pomodoroViewModel

        if pomodoro.hasActiveSession {
            if pomodoroStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    button.target = self
                    button.action = #selector(pomodoroStatusItemTapped)
                    button.sendAction(on: [.leftMouseUp])
                }
                pomodoroStatusItem = item
            }
            pomodoroStatusItem?.isVisible = true
            refreshPomodoroLabel()
            if pomodoro.isRunning {
                startTickIfNeeded()
            } else {
                stopTickIfUnused()
            }
        } else {
            pomodoroStatusItem?.isVisible = false
            stopTickIfUnused()
        }
    }

    private func refreshPomodoroLabel() {
        guard let button = pomodoroStatusItem?.button else { return }
        let pomodoro = windowController.pomodoroViewModel
        let text = pomodoro.remainingText(at: .now)
        let symbolName = pomodoro.phase.symbolName
        let cacheKey = "\(pomodoro.phase.rawValue)|\(symbolName)|\(text)"

        if cacheKey == lastRenderedTimerCacheKey, let cached = lastRenderedTimerImage {
            button.image = cached
            return
        }

        let image = generateTimerImage(
            symbolName: symbolName,
            text: text,
            color: pomodoro.phase.accentColor
        )
        lastRenderedTimerCacheKey = cacheKey
        lastRenderedTimerImage = image

        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
    }

    @objc
    private func pomodoroStatusItemTapped() {
        windowController.showFocusPanel()
    }

    private func startTickIfNeeded() {
        guard timerTick == nil else { return }
        timerTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPomodoroLabel()
            }
        }
    }

    private func stopTickIfUnused() {
        guard pomodoroStatusItem?.isVisible != true else { return }
        timerTick?.invalidate()
        timerTick = nil
    }

    private func loadStatusBarTemplateImage() -> NSImage {
        guard
            let url = Bundle.module.url(
                forResource: "status-template",
                withExtension: "png",
                subdirectory: "MenuBar"
            ),
            let image = NSImage(contentsOf: url)
        else {
            let fallback = NSImage(
                systemSymbolName: "menubar.rectangle",
                accessibilityDescription: "Notch"
            ) ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        image.isTemplate = true
        let originalSize = image.size
        let maxDimension: CGFloat = 24
        if originalSize.width > 0, originalSize.height > 0 {
            let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
            image.size = NSSize(
                width: floor(originalSize.width * scale),
                height: floor(originalSize.height * scale)
            )
        }
        return image
    }
}
