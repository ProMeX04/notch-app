import NotchFocusCore
import NotchShelfCore
import Foundation

@MainActor
final class NotchAppEnvironment {
    let entitlementStore: NotchEntitlementStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let learningStatsStore: LearningStatsStore
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let shelfViewModel: NotchShelfViewModel
    let shortcutStore: ShortcutStore
    let presentationModel: NotchPresentationModel
    let notchController: NotchWindowController
    let featureCoordinator: NotchFeatureCoordinator
    let focusBrowserBridgeServer: FocusBrowserBridgeServer

    init() {
        entitlementStore = NotchEntitlementStore()
        geminiLiveViewModel = GeminiLiveViewModel(entitlementStore: entitlementStore)
        learningStatsStore = LearningStatsStore()
        playbackViewModel = MediaProbeViewModel()
        pomodoroViewModel = PomodoroViewModel(learningStatsStore: learningStatsStore)
        focusWebsiteBlocklistStore = FocusWebsiteBlocklistStore()
        shelfViewModel = NotchShelfViewModel()
        shortcutStore = ShortcutStore()
        presentationModel = NotchPresentationModel()

        notchController = NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            shortcutStore: shortcutStore,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel,
            entitlementStore: entitlementStore
        )

        featureCoordinator = NotchFeatureCoordinator(
            windowController: notchController,
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            geminiLiveViewModel: geminiLiveViewModel,
            presentationModel: presentationModel
        )

        focusBrowserBridgeServer = FocusBrowserBridgeServer(
            pomodoroViewModel: pomodoroViewModel,
            blocklistStore: focusWebsiteBlocklistStore,
            entitlementStore: entitlementStore
        )

        GeminiLiveFeatureBridge(
            geminiLiveViewModel: geminiLiveViewModel,
            featureCoordinator: featureCoordinator,
            entitlementStore: entitlementStore,
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusBrowserBridgeServer: focusBrowserBridgeServer
        ).install()
    }
}
