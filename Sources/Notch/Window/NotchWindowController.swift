import AppKit
import Combine
import NotchFocusCore
import NotchShelfCore
import SwiftUI

@MainActor
final class NotchWindowController {
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let shelfViewModel: NotchShelfViewModel
    let shortcutStore: ShortcutStore
    let learningStatsStore: LearningStatsStore
    let presentationModel: NotchPresentationModel
    let entitlementStore: NotchEntitlementStore

    private let hostingView: NotchHostingView<MediaNotchView>
    private let window: NotchFloatingPanel
    private var cancellables = Set<AnyCancellable>()
    private let transcriptOverlay = TranscriptOverlayWindowController()
    private let liveChatInputPanel = GeminiLiveChatInputWindowController()
    private let geminiExecApprovalPanel = GeminiExecApprovalPanelController()

    private(set) var isVisible = true
    /// Emits whenever `show()`, `hide()`, or equivalent changes visibility (including initial transitions).
    let visibilityDidChange = PassthroughSubject<Bool, Never>()

    init(
        playbackViewModel: MediaProbeViewModel,
        pomodoroViewModel: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        geminiLiveViewModel: GeminiLiveViewModel,
        shelfViewModel: NotchShelfViewModel,
        shortcutStore: ShortcutStore,
        learningStatsStore: LearningStatsStore,
        presentationModel: NotchPresentationModel,
        entitlementStore: NotchEntitlementStore
    ) {
        self.playbackViewModel = playbackViewModel
        self.pomodoroViewModel = pomodoroViewModel
        self.focusWebsiteBlocklistStore = focusWebsiteBlocklistStore
        self.geminiLiveViewModel = geminiLiveViewModel
        self.shelfViewModel = shelfViewModel
        self.shortcutStore = shortcutStore
        self.learningStatsStore = learningStatsStore
        self.presentationModel = presentationModel
        self.entitlementStore = entitlementStore

        let initialScreen = NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: initialScreen)
        let initialFrame = NotchMetrics.windowFrame(on: initialScreen, selectedPanel: presentationModel.selectedPanel)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let window = NotchFloatingPanel(
            contentRect: initialFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        self.window = window
        self.hostingView = NotchHostingView(
            rootView: MediaNotchView(
                playback: playbackViewModel,
                pomodoro: pomodoroViewModel,
                focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
                gemini: geminiLiveViewModel,
                shelf: shelfViewModel,
                shortcutStore: shortcutStore,
                learningStats: learningStatsStore,
                presentationModel: presentationModel,
                entitlementStore: entitlementStore
            )
        )

        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize(for: presentationModel.selectedPanel))
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        presentationModel.$hideInFullscreen
            .sink { [weak window] hide in
                guard let window = window else { return }
                var behavior: NSWindow.CollectionBehavior = [
                    .stationary,
                    .ignoresCycle
                ]
                if hide {
                    behavior.insert(.moveToActiveSpace)
                } else {
                    behavior.insert(.canJoinAllSpaces)
                    behavior.insert(.fullScreenAuxiliary)
                }
                window.collectionBehavior = behavior
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(presentationModel.$selectedPanel, presentationModel.$isExpanded)
            .removeDuplicates(by: { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)

        transcriptOverlay.setPreferredScreen(initialScreen)
        transcriptOverlay.observe(gemini: geminiLiveViewModel)
        liveChatInputPanel.setPreferredScreen(initialScreen)
        liveChatInputPanel.observe(gemini: geminiLiveViewModel)
        geminiExecApprovalPanel.setPreferredScreen(initialScreen)
        geminiExecApprovalPanel.observe(gemini: geminiLiveViewModel)
    }

    func show() {
        isVisible = true
        visibilityDidChange.send(true)
        updateWindowFrame(animated: false)
        window.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
        visibilityDidChange.send(false)
        window.orderOut(nil)
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func showPanel(_ panel: NotchPanel) {
        show()
        presentationModel.selectPanel(panel, reveal: true)
    }

    func togglePinned() {
        presentationModel.togglePinned()
    }

    func setPinned(_ pinned: Bool) {
        guard presentationModel.isPinnedOpen != pinned else { return }
        presentationModel.togglePinned()
    }

    func reposition() {
        updateWindowFrame(animated: false)
    }

    func presentExecApproval() {
        geminiExecApprovalPanel.present(gemini: geminiLiveViewModel)
    }

    func shutdown() {
        hide()
        transcriptOverlay.stopObserving()
        liveChatInputPanel.stopObserving()
        geminiExecApprovalPanel.stopObserving()
        shelfViewModel.shutdown()
        playbackViewModel.shutdown()
        pomodoroViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }


    func updateWindowFrame(animated: Bool) {
        let currentScreen = window.screen ?? NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: currentScreen)
        let frame = NotchMetrics.windowFrame(on: currentScreen, selectedPanel: presentationModel.selectedPanel)

        // Skip the AppKit setFrame animation when nothing actually changes.
        // `windowFrame(...)` returns a constant-sized rect for the current
        // screen, so panel/expand toggles often resolve to the same frame.
        // Calling setFrame(animate: true) anyway runs an AppKit animation
        // pass that competes with the SwiftUI spring driving the notch
        // chrome, which the user perceived as drag-and-drop "khựng".
        if window.frame != frame {
            window.setFrame(frame, display: true, animate: animated)
        }

        let newSize = NotchMetrics.windowSize(for: presentationModel.selectedPanel)
        if hostingView.frame.size != newSize {
            hostingView.frame = CGRect(origin: .zero, size: newSize)
        }
        transcriptOverlay.setPreferredScreen(currentScreen)
        liveChatInputPanel.setPreferredScreen(currentScreen)

        if isVisible {
            window.orderFrontRegardless()
        }
    }
}
