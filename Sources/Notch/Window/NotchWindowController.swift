import AppKit
import Combine
import NotchFocusFeature
import NotchShelfFeature
import SwiftUI

@MainActor
final class NotchWindowController {
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let shelfViewModel: NotchShelfViewModel
    let learningStatsStore: LearningStatsStore
    let presentationModel: NotchPresentationModel
    let entitlementStore: NotchEntitlementStore

    private let hostingView: NotchHostingView<MediaNotchView>
    private let window: NotchFloatingPanel
    private var fullscreenProbeTask: Task<Void, Never>?
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
        self.learningStatsStore = learningStatsStore
        self.presentationModel = presentationModel
        self.entitlementStore = entitlementStore
        self.screen = screen
        self.screenID = NotchScreenID(screen: screen)

        let initialScreen = screen
        presentationModel.setClosedNotchSize(
            NotchMetrics.baseClosedSize(
                for: initialScreen,
                closedHeight: CGFloat(presentationModel.closedNotchHeight)
            ),
            for: screenID
        )
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
                learningStats: learningStatsStore,
                presentationModel: presentationModel,
                entitlementStore: entitlementStore,
                screenID: screenID
            )
        )

        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize(for: presentationModel.selectedPanel))
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        updateCollectionBehavior()
        updateFullscreenProbe(for: presentationModel.selectedInvisibilityMode)

        presentationModel.$invisibilityModeID
            .map(NotchInvisibilityMode.resolve(rawValue:))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.updateFullscreenProbe(for: mode)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            presentationModel.$selectedPanel,
            presentationModel.$isExpanded,
            presentationModel.$activeScreenID,
            presentationModel.$closedNotchHeight
        )
            .removeDuplicates(by: { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
            })
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

    private func updateCollectionBehavior() {
        window.collectionBehavior = [
            .stationary,
            .ignoresCycle,
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
    }

    private func updateFullscreenProbe(for mode: NotchInvisibilityMode) {
        guard mode == .fullscreenOnly else {
            stopFullscreenProbe()
            return
        }

        startFullscreenProbe()
    }

    private func startFullscreenProbe() {
        guard fullscreenProbeTask == nil else { return }
        presentationModel.setFullscreenActive(detectFullscreenWindow(), for: screenID)
        fullscreenProbeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                presentationModel.setFullscreenActive(detectFullscreenWindow(), for: screenID)
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func stopFullscreenProbe() {
        fullscreenProbeTask?.cancel()
        fullscreenProbeTask = nil
        presentationModel.setFullscreenActive(false, for: screenID)
    }

    private func detectFullscreenWindow() -> Bool {
        let screenFrame = screen.frame.integral
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        return windowList.contains { windowInfo in
            guard
                let layer = windowInfo[kCGWindowLayer as String] as? Int,
                layer == 0,
                let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID != getpid(),
                let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"],
                let y = bounds["Y"],
                let width = bounds["Width"],
                let height = bounds["Height"]
            else { return false }

            let frame = CGRect(x: x, y: y, width: width, height: height).integral
            return frame.contains(screenFrame) || frame.equalTo(screenFrame)
        }
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
        stopFullscreenProbe()
        cancellables.removeAll()
    }


    func updateWindowFrame(animated: Bool) {
        let currentScreen = screen
        presentationModel.setClosedNotchSize(
            NotchMetrics.baseClosedSize(
                for: currentScreen,
                closedHeight: CGFloat(presentationModel.closedNotchHeight)
            ),
            for: screenID
        )
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
