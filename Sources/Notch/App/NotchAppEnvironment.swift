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
    let notchController: NotchWindowManager
    let featureCoordinator: NotchFeatureCoordinator
    let focusBrowserBridgeServer: FocusBrowserBridgeServer
    let appSettingsController: AppSettingsControlling

    init(appSettingsController: AppSettingsControlling = AppSettingsController.shared) {
        self.appSettingsController = appSettingsController
        entitlementStore = NotchEntitlementStore()
        let geminiDependencies = GeminiLiveViewModelDependencies.live(
            entitlementStore: entitlementStore
        )
        geminiLiveViewModel = GeminiLiveViewModel(dependencies: geminiDependencies)
        learningStatsStore = LearningStatsStore()
        playbackViewModel = MediaProbeViewModel()
        pomodoroViewModel = PomodoroViewModel(learningStatsStore: learningStatsStore)
        focusWebsiteBlocklistStore = FocusWebsiteBlocklistStore()
        shelfViewModel = NotchShelfViewModel()
        shortcutStore = ShortcutStore()
        presentationModel = NotchPresentationModel()

        notchController = NotchWindowManager(
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
            presentationModel: presentationModel,
            appSettingsController: appSettingsController
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
