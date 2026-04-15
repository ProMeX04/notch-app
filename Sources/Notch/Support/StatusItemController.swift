import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let windowController: NotchWindowController
    private let launchAtLoginController = LaunchAtLoginController()
    private var cancellables = Set<AnyCancellable>()
    private var taskPopover: NSPopover?

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
        title: "Gemini Settings…",
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
        Publishers.CombineLatest3(
            pomo.$isRunning,
            pomo.$hasActiveSession,
            pomo.$selectedTaskId
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

    private func generateTimerImage(symbolName: String, text: String, task: String, color: NSColor) -> NSImage {
        let timerFontSize: CGFloat = 14.2
        let taskFontSize: CGFloat = 13.8
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: timerFontSize, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        // Slightly wider for the new font size
        let timerFixedWidth: CGFloat = 48 
        let timerSize = text.size(withAttributes: textAttributes)
        
        // Task attributes - now closer to timer size
        let taskFont = NSFont.systemFont(ofSize: taskFontSize, weight: .bold)
        let taskAttributes: [NSAttributedString.Key: Any] = [
            .font: taskFont,
            .foregroundColor: color.withAlphaComponent(0.9)
        ]
        
        // Limit task by width (pt), not character count — fairer for Vietnamese / mixed scripts.
        let maxTaskWidth: CGFloat = 280
        let displayTask = Self.truncateToWidth(task, maxWidth: maxTaskWidth, attributes: taskAttributes)
        let taskSize = displayTask.isEmpty ? .zero : displayTask.size(withAttributes: taskAttributes)

        let config = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .bold)
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
        let paddingX: CGFloat = 8
        let spacing: CGFloat = 6
        let height: CGFloat = 22
        
        // Calculate raw width
        var innerWidth = paddingX + symbolSize.width + spacing + timerFixedWidth
        if !displayTask.isEmpty {
            innerWidth += spacing + 1 + spacing + taskSize.width // spacing + separator + spacing + task
        }
        innerWidth += paddingX
        
        // Round up to nearest 4 pixels to stabilize Menu Bar interaction
        let width = ceil(innerWidth / 4.0) * 4.0

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
            NSColor(white: 0.05, alpha: 1.0).setFill()
            path.fill()

            // Draw Symbol
            let symbolRect = NSRect(
                x: paddingX,
                y: (rect.height - symbolSize.height) / 2.0,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbolImage.draw(in: symbolRect)

            // Draw Timer Text (Centered in its fixed width area)
            let timerX = paddingX + symbolSize.width + spacing
            let timerRect = NSRect(
                x: timerX + (timerFixedWidth - timerSize.width) / 2.0,
                y: (rect.height - timerSize.height) / 2.0 - 0.5,
                width: timerSize.width,
                height: timerSize.height
            )
            text.draw(in: timerRect, withAttributes: textAttributes)
            
            // Draw Task Text if exists
            if !displayTask.isEmpty {
                let sepX = timerX + timerFixedWidth + spacing
                let sepPath = NSBezierPath()
                sepPath.move(to: NSPoint(x: sepX, y: 6))
                sepPath.line(to: NSPoint(x: sepX, y: height - 6))
                color.withAlphaComponent(0.2).setStroke()
                sepPath.lineWidth = 1
                sepPath.stroke()
                
                let taskRect = NSRect(
                    x: sepX + spacing,
                    y: (rect.height - taskSize.height) / 2.0 - 0.5,
                    width: taskSize.width,
                    height: taskSize.height
                )
                displayTask.draw(in: taskRect, withAttributes: taskAttributes)
            }
            
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Truncates with ellipsis when the rendered width exceeds `maxWidth` (uses same font as drawing).
    private static func truncateToWidth(_ string: String, maxWidth: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        guard !string.isEmpty else { return "" }
        let ns = string as NSString
        if ns.size(withAttributes: attributes).width <= maxWidth {
            return string
        }
        let ellipsis = "…"
        let ellipsisWidth = (ellipsis as NSString).size(withAttributes: attributes).width
        var low = 0
        var high = string.count
        while low < high {
            let mid = (low + high + 1) / 2
            let prefix = String(string.prefix(mid))
            let w = (prefix as NSString).size(withAttributes: attributes).width + ellipsisWidth
            if w <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        if low == 0 { return ellipsis }
        return String(string.prefix(low)) + ellipsis
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
        let taskForBar = pomodoro.currentTask
        let cacheKey = "\(pomodoro.phase.rawValue)|\(symbolName)|\(text)|\(taskForBar)"

        if cacheKey == lastRenderedTimerCacheKey, let cached = lastRenderedTimerImage {
            button.image = cached
            return
        }

        let image = generateTimerImage(
            symbolName: symbolName,
            text: text,
            task: taskForBar,
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
        guard let button = pomodoroStatusItem?.button else { return }
        
        if taskPopover == nil {
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 320, height: 380)
            popover.behavior = .transient
            popover.animates = true
            
            let contentView = TaskPopoverView(
                pomodoro: windowController.pomodoroViewModel,
                onOpenNotch: { [weak self] in
                    self?.taskPopover?.performClose(nil)
                    self?.windowController.showFocusPanel()
                }
            )
            
            popover.contentViewController = NSHostingController(rootView: contentView)
            taskPopover = popover
        }
        
        if taskPopover?.isShown == true {
            taskPopover?.performClose(nil)
        } else {
            taskPopover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the popover window is styled appropriately
            if let window = taskPopover?.contentViewController?.view.window {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .clear
            }
        }
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

// MARK: - Task Popover View

import SwiftUI

struct TaskPopoverView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    var onOpenNotch: () -> Void
    
    @State private var newTaskTitle: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    /// Task selection chrome follows app accent, not Pomodoro phase.
    private var taskSelectionTint: Color {
        NotchAccentColorOption.resolve(rawValue: accentColorID).color.ensureMinimumBrightness(factor: 0.78)
    }

    private var isLightChrome: Bool { colorScheme == .light }

    /// Foreground / field colors: `NotchPanelFieldMetrics` assumes dark chrome; menu bar popover is light in Light Mode.
    private var primaryLabel: Color { isLightChrome ? Color.black.opacity(0.88) : Color.white }
    private var secondaryLabel: Color { isLightChrome ? Color.black.opacity(0.42) : Color.white.opacity(0.4) }
    private var tertiaryLabel: Color { isLightChrome ? Color.black.opacity(0.35) : Color.white.opacity(0.35) }
    private var bodyText: Color { isLightChrome ? Color.black.opacity(0.78) : Color.white.opacity(0.78) }
    private var bodyTextEmphasis: Color { isLightChrome ? Color.black.opacity(0.92) : Color.white.opacity(0.95) }
    private var fieldFillColor: Color { isLightChrome ? Color.black.opacity(0.05) : NotchPanelFieldMetrics.fieldFill }
    private var fieldStrokeColor: Color { isLightChrome ? Color.black.opacity(0.11) : NotchPanelFieldMetrics.fieldStroke }
    private var subtleIcon: Color { isLightChrome ? Color.black.opacity(0.32) : Color.white.opacity(0.38) }
    private var completedTaskText: Color { isLightChrome ? Color.black.opacity(0.38) : Color.white.opacity(0.38) }
    private var sessionCapsuleFill: Color { isLightChrome ? Color.black.opacity(0.07) : Color.white.opacity(0.08) }

    private var openTasks: [FocusTask] {
        pomodoro.tasks.filter { !$0.isCompleted }
    }

    private var doneTasks: [FocusTask] {
        pomodoro.tasks.filter { $0.isCompleted }
    }

    private var focusControlTitle: String {
        if pomodoro.isRunning {
            return Localization.get("Pause", lang: appLanguage)
        }
        if pomodoro.hasActiveSession {
            return Localization.get("Resume", lang: appLanguage)
        }
        return Localization.get("Start Focus", lang: appLanguage)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Header: current task + start / pause / resume
                HStack(alignment: .center, spacing: 12) {
                    Text(pomodoro.currentTask.isEmpty ? Localization.get("Tasks", lang: appLanguage) : pomodoro.currentTask)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryLabel)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StandardActionButton(
                        title: focusControlTitle,
                        icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                        tint: taskSelectionTint,
                        variant: .primary,
                        action: { pomodoro.toggleRunning() }
                    )
                }
                .padding(.bottom, 16)

                // Scrollable Task List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        // Compact Add Field (chrome aligned with Notch menu fields)
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(NotchPanelFieldMetrics.labelFont)
                                .foregroundStyle(subtleIcon)
                                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)
                            
                            TextField(Localization.get("What are you working on?", lang: appLanguage), text: $newTaskTitle)
                                .textFieldStyle(.plain)
                                .font(NotchPanelFieldMetrics.labelFont)
                                .foregroundStyle(bodyTextEmphasis)
                                .focused($isTextFieldFocused)
                                .onSubmit(addTask)
                            
                            if !newTaskTitle.isEmpty {
                                StandardActionButton(
                                    title: Localization.get("Add", lang: appLanguage),
                                    icon: "plus.circle.fill",
                                    tint: taskSelectionTint,
                                    variant: .primary,
                                    action: addTask
                                )
                            }
                        }
                        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
                        .padding(.vertical, NotchPanelFieldMetrics.vPad)
                        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
                        .background(
                            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                                .fill(fieldFillColor)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                                .stroke(fieldStrokeColor, lineWidth: 1)
                        }
                        .padding(.bottom, 8)

                        // Tasks: open vs completed
                        if !pomodoro.tasks.isEmpty {
                            if !openTasks.isEmpty {
                                taskSectionHeader(Localization.get("Open tasks", lang: appLanguage))
                                ForEach(openTasks) { task in
                                    popoverTaskRow(for: task)
                                }
                            }

                            if !doneTasks.isEmpty {
                                taskSectionHeader(Localization.get("Completed tasks", lang: appLanguage))
                                    .padding(.top, openTasks.isEmpty ? 0 : 10)
                                ForEach(doneTasks) { task in
                                    popoverTaskRow(for: task)
                                }
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 24))
                                    .foregroundStyle(isLightChrome ? Color.black.opacity(0.12) : Color.white.opacity(0.1))
                                Text(Localization.get("No tasks yet", lang: appLanguage))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(tertiaryLabel)
                            }
                            .padding(.vertical, 40)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 320, height: 380)
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow).ignoresSafeArea())
    }

    private func taskSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(tertiaryLabel)
                .tracking(1.2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func popoverTaskRow(for task: FocusTask) -> some View {
        let isSelected = pomodoro.selectedTaskId == task.id
        let tint = taskSelectionTint
        
        return HStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.2)) {
                    if let index = pomodoro.tasks.firstIndex(where: { $0.id == task.id }) {
                        pomodoro.tasks[index].isCompleted.toggle()
                    }
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.isCompleted ? .green : subtleIcon)
                    .frame(width: NotchPanelFieldMetrics.iconColWidth, height: NotchPanelFieldMetrics.minHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    pomodoro.selectedTaskId = isSelected ? nil : task.id
                }
            } label: {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? completedTaskText : (isSelected ? bodyTextEmphasis : bodyText))
                        .lineLimit(2)
                    
                    if task.completedSessions > 0 {
                        Text("\(task.completedSessions)")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(isSelected ? tint : (isLightChrome ? Color.black.opacity(0.4) : Color.white.opacity(0.4)))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(isSelected ? tint.opacity(0.15) : sessionCapsuleFill)
                            )
                    }

                    if isSelected {
                        Image(systemName: "timer")
                            .font(NotchPanelFieldMetrics.chevronFont)
                            .foregroundStyle(tint)
                    }
                    
                    Spacer()
                }
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, minHeight: NotchPanelFieldMetrics.minHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation {
                    if pomodoro.selectedTaskId == task.id {
                        pomodoro.selectedTaskId = nil
                    }
                    pomodoro.tasks.removeAll { $0.id == task.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(NotchPanelFieldMetrics.chevronFont)
                    .foregroundStyle(subtleIcon)
                    .frame(width: NotchPanelFieldMetrics.iconColWidth, height: NotchPanelFieldMetrics.minHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                .fill(isSelected ? tint.opacity(0.12) : fieldFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.4) : fieldStrokeColor, lineWidth: 1)
        )
    }

    private func addTask() {
        guard !newTaskTitle.isEmpty else { return }
        let task = FocusTask(title: newTaskTitle)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            pomodoro.tasks.insert(task, at: 0)
            if pomodoro.selectedTaskId == nil {
                pomodoro.selectedTaskId = task.id
            }
            newTaskTitle = ""
        }
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
