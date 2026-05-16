import AppKit
import Combine
import NotchFocusCore
import NotchShelfCore

@MainActor
final class NotchWindowManager {
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let shelfViewModel: NotchShelfViewModel
    let shortcutStore: ShortcutStore
    let learningStatsStore: LearningStatsStore
    let presentationModel: NotchPresentationModel
    let entitlementStore: NotchEntitlementStore

    private var controllers: [NotchScreenID: NotchWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let transcriptOverlay = TranscriptOverlayWindowController()
    private let liveChatInputPanel = GeminiLiveChatInputWindowController()
    private let geminiExecApprovalPanel = GeminiExecApprovalPanelController()

    private(set) var isVisible = true
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

        syncControllers(repositionSingleToCursor: true)
        observeSharedState()
        transcriptOverlay.observe(gemini: geminiLiveViewModel)
        liveChatInputPanel.observe(gemini: geminiLiveViewModel)
        geminiExecApprovalPanel.observe(gemini: geminiLiveViewModel)
        updateOverlayScreen()
    }

    func show() {
        isVisible = true
        visibilityDidChange.send(true)
        syncControllers(repositionSingleToCursor: false)
        controllers.values.forEach { $0.show() }
        updateOverlayScreen()
    }

    func hide() {
        isVisible = false
        visibilityDidChange.send(false)
        controllers.values.forEach { $0.hide() }
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func showPanel(_ panel: NotchPanel) {
        syncControllers(repositionSingleToCursor: false)
        let controller = activeController() ?? preferredController()
        controller?.showPanel(panel)
        if isVisible {
            controllers.values.forEach { $0.show() }
        }
        updateOverlayScreen()
    }

    func reposition() {
        syncControllers(repositionSingleToCursor: true)
        updateOverlayScreen()
    }

    func presentExecApproval() {
        updateOverlayScreen()
        geminiExecApprovalPanel.present(gemini: geminiLiveViewModel)
    }

    func shutdown() {
        hide()
        transcriptOverlay.stopObserving()
        liveChatInputPanel.stopObserving()
        geminiExecApprovalPanel.stopObserving()
        controllers.values.forEach { $0.shutdown(shutdownSharedModels: false) }
        controllers.removeAll()
        shelfViewModel.shutdown()
        playbackViewModel.shutdown()
        pomodoroViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }

    private func observeSharedState() {
        presentationModel.$screenDisplayModeID
            .dropFirst()
            .sink { [weak self] modeID in
                self?.syncControllers(
                    mode: NotchScreenDisplayMode.resolve(rawValue: modeID),
                    repositionSingleToCursor: true
                )
            }
            .store(in: &cancellables)

        presentationModel.$activeScreenID
            .sink { [weak self] _ in
                self?.updateOverlayScreen()
            }
            .store(in: &cancellables)
    }

    private func syncControllers(
        mode: NotchScreenDisplayMode? = nil,
        repositionSingleToCursor: Bool
    ) {
        let screens = NSScreen.screens
        let displayMode = mode ?? presentationModel.selectedScreenDisplayMode
        let targetScreens: [NSScreen]
        switch displayMode {
        case .oneScreen:
            targetScreens = preferredSingleScreens(repositionSingleToCursor: repositionSingleToCursor, fallbackScreens: screens)
        case .allScreens:
            targetScreens = screens
        }

        let targetIDs = Set(targetScreens.map(NotchScreenID.init(screen:)))
        let removedIDs = controllers.keys.filter { !targetIDs.contains($0) }
        for screenID in removedIDs {
            guard let controller = controllers.removeValue(forKey: screenID) else { continue }
            controller.hide()
            controller.shutdown(shutdownSharedModels: false)
            presentationModel.removeScreenState(for: screenID)
        }

        for screen in targetScreens {
            let screenID = NotchScreenID(screen: screen)
            if let controller = controllers[screenID] {
                controller.retarget(to: screen)
                if isVisible {
                    controller.show()
                }
            } else {
                let controller = makeController(screen: screen)
                controllers[screenID] = controller
                if isVisible {
                    controller.show()
                } else {
                    controller.hide()
                }
            }
        }
    }

    private func preferredSingleScreens(repositionSingleToCursor: Bool, fallbackScreens: [NSScreen]) -> [NSScreen] {
        if repositionSingleToCursor, let preferredScreen = NotchMetrics.preferredScreen() {
            return [preferredScreen]
        }

        if !repositionSingleToCursor {
            if let screen = activeController()?.screen ?? controllers.values.first?.screen ?? NotchMetrics.preferredScreen() {
                return [screen]
            }
        }

        return fallbackScreens.prefix(1).map { $0 }
    }

    private func makeController(screen: NSScreen) -> NotchWindowController {
        NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            shortcutStore: shortcutStore,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel,
            entitlementStore: entitlementStore,
            screen: screen
        )
    }

    private func activeController() -> NotchWindowController? {
        presentationModel.activeScreenID.flatMap { controllers[$0] }
    }

    private func preferredController() -> NotchWindowController? {
        if let preferredScreen = NotchMetrics.preferredScreen() {
            return controllers[NotchScreenID(screen: preferredScreen)]
        }
        return controllers.values.first
    }

    private func updateOverlayScreen() {
        let screen = activeController()?.screen ?? preferredController()?.screen ?? NotchMetrics.preferredScreen()
        transcriptOverlay.setPreferredScreen(screen)
        liveChatInputPanel.setPreferredScreen(screen)
        geminiExecApprovalPanel.setPreferredScreen(screen)
    }
}
