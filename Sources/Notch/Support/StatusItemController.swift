import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let windowController: NotchWindowController
    private let launchAtLoginController = LaunchAtLoginController()
    private var cancellables = Set<AnyCancellable>()

    // Live timer menu bar item for the active Pomodoro session.
    private var pomodoroStatusItem: NSStatusItem?
    /// Transient chip when Gemini runs a tool (mirrors `lastToolAction` toast).
    private var geminiToolStatusItem: NSStatusItem?
    private var timerTick: Timer?

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

    private lazy var musicItem = NSMenuItem(
        title: "Open Media",
        action: #selector(showMusicPanel),
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
        musicItem.target = self
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
            musicItem,
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

        // Observe pomodoro session state
        let pomo = windowController.pomodoroViewModel
        Publishers.CombineLatest(
            pomo.$isRunning,
            pomo.$hasActiveSession
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshAllFocusStatusItems() }
        .store(in: &cancellables)

        windowController.geminiLiveViewModel.$lastToolAction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateGeminiToolStatusItem() }
            .store(in: &cancellables)

        refreshAllFocusStatusItems()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginController.refreshStatus()
        visibilityItem.title = windowController.isVisible ? "Hide Notch" : "Show Notch"
        pinItem.state = windowController.presentationModel.isPinnedOpen ? .on : .off
        musicItem.state = windowController.presentationModel.selectedPanel == .music ? .on : .off
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
            togglePomodoroItem.isEnabled = true
        } else if windowController.pomodoroViewModel.hasActiveSession {
            togglePomodoroItem.title = "Resume Pomodoro"
            togglePomodoroItem.isEnabled = true
        } else {
            togglePomodoroItem.title = "Start Pomodoro"
            togglePomodoroItem.isEnabled = true
        }

        resetPomodoroItem.title = "Reset Pomodoro"
        resetPomodoroItem.isEnabled = windowController.pomodoroViewModel.hasActiveSession
    }

    @objc
    private func toggleVisibility() {
        windowController.toggleVisibility()
    }

    @objc
    private func togglePinned() {
        windowController.presentationModel.togglePinned()
    }

    @objc
    private func showMusicPanel() {
        windowController.showMusicPanel()
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
        windowController.togglePomodoroSession()
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
        windowController.resetPomodoroFromUI()
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

    // MARK: - Live Timer Menu Bar Item

    private func generateTimerImage(symbolName: String, text: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14.5, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = text.size(withAttributes: textAttributes)
        
        let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .bold)
        guard let symbolBase = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        
        let symbolImage = NSImage(size: symbolBase.size, flipped: false) { rect in
             if symbolBase.size.width > 0 {
                 symbolBase.draw(in: rect)
                 color.set()
                 rect.fill(using: .sourceAtop)
             }
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

    // MARK: Pomodoro status item

    private func refreshAllFocusStatusItems() {
        updatePomodoroStatusItem()
    }

    private func updatePomodoroStatusItem() {
        let pomo = windowController.pomodoroViewModel

        if pomo.hasActiveSession {
            if pomodoroStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let btn = item.button {
                    btn.target = self
                    btn.action = #selector(pomodoroStatusItemTapped)
                    btn.sendAction(on: [.leftMouseUp])
                }
                pomodoroStatusItem = item
            }
            pomodoroStatusItem?.isVisible = true
            refreshPomodoroLabel()
            if pomo.isRunning {
                startTickIfNeeded()
            } else {
                stopTickIfUnused()
            }
        } else {
            pomodoroStatusItem?.isVisible = false
            stopTickIfUnused()
        }
    }

    private var lastRenderedTimerText: String?
    private var lastRenderedTimerImage: NSImage?

    private func refreshPomodoroLabel() {
        guard let btn = pomodoroStatusItem?.button else { return }
        let pomo = windowController.pomodoroViewModel
        let text = pomo.remainingText(at: .now)
        let symbolName = pomo.phase == .focus ? "timer" : "cup.and.saucer.fill"
        
        if text == lastRenderedTimerText, let cached = lastRenderedTimerImage {
            btn.image = cached
            return
        }

        let image = generateTimerImage(symbolName: symbolName, text: text, color: pomo.phase.accentColor)
        lastRenderedTimerText = text
        lastRenderedTimerImage = image
        
        btn.image = image
        btn.title = ""
        btn.imagePosition = .imageOnly
    }

    @objc
    private func pomodoroStatusItemTapped() {
        windowController.showFocusPanel()
    }

    // MARK: Gemini tool activity (menu bar)

    private func updateGeminiToolStatusItem() {
        let toast = windowController.geminiLiveViewModel.lastToolAction
        if let toast {
            if geminiToolStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let btn = item.button {
                    btn.target = self
                    btn.action = #selector(geminiToolStatusItemTapped)
                    btn.sendAction(on: [.leftMouseUp])
                }
                geminiToolStatusItem = item
            }
            refreshGeminiToolStatusItem(toast: toast)
        } else {
            if let item = geminiToolStatusItem {
                NSStatusBar.system.removeStatusItem(item)
                geminiToolStatusItem = nil
            }
        }
    }

    private func refreshGeminiToolStatusItem(toast: ToolActionToast) {
        guard let btn = geminiToolStatusItem?.button else { return }
        let maxLen = 24
        let truncated =
            toast.label.count > maxLen ? String(toast.label.prefix(maxLen)) + "…" : toast.label
        let symbolName = NSImage(systemSymbolName: toast.icon, accessibilityDescription: toast.label) == nil
            ? "wrench.and.screwdriver"
            : toast.icon
        btn.image = generateTimerImage(
            symbolName: symbolName,
            text: truncated,
            color: geminiToolStatusColor(for: toast)
        )
        btn.title = ""
        btn.imagePosition = .imageOnly
        btn.toolTip = toast.label
    }

    private func geminiToolStatusColor(for toast: ToolActionToast) -> NSColor {
        switch toast.icon {
        case "exclamationmark.triangle":
            return .systemRed
        case "terminal":
            return .systemGreen
        case "square.and.pencil", "slider.horizontal.below.rectangle":
            return .systemOrange
        case "folder", "doc.text":
            return .systemTeal
        case "magnifyingglass", "text.magnifyingglass":
            return .systemBlue
        default:
            return .systemBlue
        }
    }

    @objc
    private func geminiToolStatusItemTapped() {
        windowController.showTalkPanel()
    }

    // MARK: Shared tick timer

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
            let url = Bundle.module.url(forResource: "status-template", withExtension: "png", subdirectory: "MenuBar"),
            let image = NSImage(contentsOf: url)
        else {
            let fallback = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Notch") ?? NSImage()
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
