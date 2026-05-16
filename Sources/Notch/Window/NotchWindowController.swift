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
    private(set) var screen: NSScreen
    let screenID: NotchScreenID
    private var cancellables = Set<AnyCancellable>()

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
        entitlementStore: NotchEntitlementStore,
        screen: NSScreen
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
        self.screen = screen
        self.screenID = NotchScreenID(screen: screen)

        let initialScreen = screen
        presentationModel.setClosedNotchSize(NotchMetrics.baseClosedSize(for: initialScreen), for: screenID)
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
                entitlementStore: entitlementStore,
                screenID: screenID
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

        Publishers.CombineLatest3(presentationModel.$selectedPanel, presentationModel.$isExpanded, presentationModel.$activeScreenID)
            .removeDuplicates(by: { lhs, rhs in lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)
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
        presentationModel.selectPanel(panel, on: screenID, reveal: true)
    }

    func retarget(to screen: NSScreen) {
        self.screen = screen
        updateWindowFrame(animated: false)
    }

    func reposition() {
        updateWindowFrame(animated: false)
    }

    func shutdown(shutdownSharedModels: Bool = true) {
        hide()
        if shutdownSharedModels {
            shelfViewModel.shutdown()
            playbackViewModel.shutdown()
            pomodoroViewModel.shutdown()
            geminiLiveViewModel.shutdown()
        }
        cancellables.removeAll()
    }


    func updateWindowFrame(animated: Bool) {
        let currentScreen = screen
        presentationModel.setClosedNotchSize(NotchMetrics.baseClosedSize(for: currentScreen), for: screenID)
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
        if isVisible {
            window.orderFrontRegardless()
        }
    }
}
