import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let windowController: NotchWindowController
    private let launchAtLoginController = LaunchAtLoginController()
    private var cancellables = Set<AnyCancellable>()

    // Live timer menu bar items — one per tool
    private var pomodoroStatusItem: NSStatusItem?
    private var countdownStatusItem: NSStatusItem?
    private var counterStatusItem: NSStatusItem?
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

        // Observe pomodoro session state
        let pomo = windowController.pomodoroViewModel
        let countdown = windowController.countdownViewModel

        Publishers.CombineLatest(
            pomo.$isRunning,
            pomo.$hasActiveSession
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshAllFocusStatusItems() }
        .store(in: &cancellables)

        // Observe countdown session state
        Publishers.CombineLatest(
            countdown.$isRunning,
            countdown.$hasActiveSession
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshAllFocusStatusItems() }
        .store(in: &cancellables)

        // Observe stopwatch (counter) session state
        let counter = windowController.counterViewModel
        Publishers.CombineLatest(
            counter.$isRunning,
            counter.$hasActiveSession
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

        let focusToolTitle = selectedFocusToolTitle

        if selectedFocusToolIsRunning {
            togglePomodoroItem.title = "Pause \(focusToolTitle)"
            togglePomodoroItem.isEnabled = true
        } else if selectedFocusToolHasSession {
            togglePomodoroItem.title = "Resume \(focusToolTitle)"
            togglePomodoroItem.isEnabled = true
        } else {
            togglePomodoroItem.title = "Start \(focusToolTitle)"
            togglePomodoroItem.isEnabled = true
        }

        resetPomodoroItem.title = "Reset \(focusToolTitle)"
        resetPomodoroItem.isEnabled = selectedFocusToolHasSession
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
        windowController.toggleSelectedFocusTool()
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
        windowController.resetSelectedFocusTool()
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

    private var selectedFocusToolTitle: String {
        switch windowController.presentationModel.selectedFocusTool {
        case .pomodoro:
            return "Pomodoro"
        case .countdown:
            return "Countdown"
        case .counter:
            return "Stopwatch"
        }
    }

    private var selectedFocusToolIsRunning: Bool {
        switch windowController.presentationModel.selectedFocusTool {
        case .pomodoro:
            return windowController.pomodoroViewModel.isRunning
        case .countdown:
            return windowController.countdownViewModel.isRunning
        case .counter:
            return windowController.counterViewModel.isRunning
        }
    }

    private var selectedFocusToolHasSession: Bool {
        switch windowController.presentationModel.selectedFocusTool {
        case .pomodoro:
            return windowController.pomodoroViewModel.hasActiveSession
        case .countdown:
            return windowController.countdownViewModel.hasActiveSession
        case .counter:
            return windowController.counterViewModel.hasActiveSession
        }
    }

    // MARK: - Live Timer Menu Bar Items

    private func generateTimerImage(symbolName: String, text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.systemGreen
        ]
        let textSize = text.size(withAttributes: textAttributes)
        
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let symbolBase = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return NSImage() }
        
        let symbolImage = NSImage(size: symbolBase.size, flipped: false) { rect in
             if symbolBase.size.width > 0 {
                 symbolBase.draw(in: rect)
                 NSColor.systemGreen.set()
                 rect.fill(using: .sourceAtop)
             }
             return true
        }
        
        let symbolSize = symbolImage.size
        let paddingX: CGFloat = 8
        let spacing: CGFloat = 4
        let height: CGFloat = 20
        let width = paddingX + symbolSize.width + spacing + textSize.width + paddingX
        
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 6.5, yRadius: 6.5)
            NSColor(white: 0.0, alpha: 0.35).setFill()
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
        updateCountdownStatusItem()
        updateCounterStatusItem()
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
            startTickIfNeeded()
            refreshPomodoroLabel()
        } else {
            pomodoroStatusItem?.isVisible = false
            stopTickIfUnused()
        }
    }

    private func refreshPomodoroLabel() {
        guard let btn = pomodoroStatusItem?.button else { return }
        let pomo = windowController.pomodoroViewModel
        let symbolName = pomo.phase == .focus ? "timer" : "cup.and.saucer.fill"
        btn.image = generateTimerImage(symbolName: symbolName, text: pomo.remainingText(at: .now))
        btn.title = ""
        btn.imagePosition = .imageOnly
    }

    @objc
    private func pomodoroStatusItemTapped() {
        windowController.showFocusPanel()
        windowController.presentationModel.selectedFocusTool = .pomodoro
    }

    // MARK: Countdown status item

    private func updateCountdownStatusItem() {
        let countdown = windowController.countdownViewModel

        if countdown.hasActiveSession {
            if countdownStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let btn = item.button {
                    btn.target = self
                    btn.action = #selector(countdownStatusItemTapped)
                    btn.sendAction(on: [.leftMouseUp])
                }
                countdownStatusItem = item
            }
            countdownStatusItem?.isVisible = true
            startTickIfNeeded()
            refreshCountdownLabel()
        } else {
            countdownStatusItem?.isVisible = false
            stopTickIfUnused()
        }
    }

    private func refreshCountdownLabel() {
        guard let btn = countdownStatusItem?.button else { return }
        let countdown = windowController.countdownViewModel
        btn.image = generateTimerImage(symbolName: "hourglass", text: countdown.remainingText(at: .now))
        btn.title = ""
        btn.imagePosition = .imageOnly
    }

    @objc
    private func countdownStatusItemTapped() {
        windowController.showFocusPanel()
        windowController.presentationModel.selectedFocusTool = .countdown
    }

    // MARK: Stopwatch (counter) status item

    private func updateCounterStatusItem() {
        let counter = windowController.counterViewModel

        if counter.hasActiveSession {
            if counterStatusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let btn = item.button {
                    btn.target = self
                    btn.action = #selector(counterStatusItemTapped)
                    btn.sendAction(on: [.leftMouseUp])
                }
                counterStatusItem = item
            }
            counterStatusItem?.isVisible = true
            startTickIfNeeded()
            refreshCounterLabel()
        } else {
            counterStatusItem?.isVisible = false
            stopTickIfUnused()
        }
    }

    private func refreshCounterLabel() {
        guard let btn = counterStatusItem?.button else { return }
        let counter = windowController.counterViewModel
        btn.image = generateTimerImage(symbolName: "stopwatch", text: counter.elapsedText(at: .now))
        btn.title = ""
        btn.imagePosition = .imageOnly
    }

    @objc
    private func counterStatusItemTapped() {
        windowController.showFocusPanel()
        windowController.presentationModel.selectedFocusTool = .counter
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
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let symbol = NSImage(systemSymbolName: toast.icon, accessibilityDescription: toast.label)?
            .withSymbolConfiguration(config)
        if let symbol {
            symbol.isTemplate = true
            btn.image = symbol
        } else {
            let fallback = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: toast.label)
            fallback?.isTemplate = true
            btn.image = fallback
        }
        let maxLen = 32
        let truncated =
            toast.label.count > maxLen ? String(toast.label.prefix(maxLen)) + "…" : toast.label
        btn.title = truncated
        btn.imagePosition = .imageLeading
        btn.toolTip = toast.label
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
                self?.refreshCountdownLabel()
                self?.refreshCounterLabel()
            }
        }
    }

    private func stopTickIfUnused() {
        guard
            pomodoroStatusItem?.isVisible != true,
            countdownStatusItem?.isVisible != true,
            counterStatusItem?.isVisible != true
        else { return }
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
