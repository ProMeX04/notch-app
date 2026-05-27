import NotchFocusFeature
import NotchShelfFeature
import Foundation

@MainActor
final class NotchAppEnvironment {
    let entitlementStore: NotchEntitlementStore
    let portalAccountCoordinator: PortalAccountCoordinator
    let geminiLiveViewModel: GeminiLiveViewModel
    let learningStatsStore: LearningStatsStore
    let focusDailyStatsRepository: FocusDailyStatsRepository
    let focusCloudSyncService: FocusCloudSyncCoordinator
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
        let portalAPIClient = PortalAPIClient()
        portalAccountCoordinator = PortalAccountCoordinator(
            client: portalAPIClient,
            configStore: PortalConfigurationStore(processInfo: .processInfo),
            authStore: PortalAuthStore(processInfo: .processInfo),
            entitlementStore: entitlementStore
        )
        let geminiDependencies = GeminiLiveViewModelDependencies.live(
            entitlementStore: entitlementStore,
            portalAccount: portalAccountCoordinator,
            portalClient: portalAPIClient
        )
        geminiLiveViewModel = GeminiLiveViewModel(dependencies: geminiDependencies)
        learningStatsStore = LearningStatsStore()
        focusDailyStatsRepository = FocusDailyStatsRepository()
        focusCloudSyncService = FocusCloudSyncCoordinator(
            repository: focusDailyStatsRepository,
            portalAccount: portalAccountCoordinator,
            portalClient: URLSessionFocusPortalClient()
        )
        playbackViewModel = MediaProbeViewModel()
        pomodoroViewModel = PomodoroViewModel(
            learningStatsRecorder: FocusStatsRecorder(
                localStats: learningStatsStore,
                dailyStats: focusDailyStatsRepository
            )
        )
        focusWebsiteBlocklistStore = FocusWebsiteBlocklistStore()
        shelfViewModel = NotchShelfViewModel()

        let portalAccount = portalAccountCoordinator
        let getPortalURL: () -> URL = { [weak portalAccount] in
            if let custom = UserDefaults.standard.string(forKey: "notch_portal_url"),
               let url = URL(string: custom) {
                return url
            }
            return portalAccount?.portalBaseURL ?? URL(string: PortalHostedBackend.defaultURL)!
        }

        shelfViewModel.portalBaseURLProvider = getPortalURL
        shelfViewModel.applyRetentionPolicy(shelfViewModel.preferences.retentionPolicy)

        shelfViewModel.onConnectGoogleDriveRequested = { state, codeChallenge in
            let portalBaseURL = getPortalURL()
            let authURL = NotchWebPortal.googleDriveAuthURL(
                apiBaseURL: portalBaseURL,
                state: state,
                codeChallenge: codeChallenge
            )
            NotchWebPortal.openInBrowser(authURL)
        }

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
            portalAccountCoordinator: portalAccountCoordinator,
            shelfViewModel: shelfViewModel,
            presentationModel: presentationModel,
            appSettingsController: appSettingsController
        )

        focusBrowserBridgeServer = FocusBrowserBridgeServer(
            pomodoroViewModel: pomodoroViewModel,
            blocklistStore: focusWebsiteBlocklistStore,
            entitlementStore: entitlementStore
        )

        let geminiLiveFeatureBridge = GeminiLiveFeatureBridge(
            geminiLiveViewModel: geminiLiveViewModel,
            featureCoordinator: featureCoordinator,
            entitlementStore: entitlementStore,
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusBrowserBridgeServer: focusBrowserBridgeServer
        )
        geminiLiveFeatureBridge.install()

        let previousAuthChanged = portalAccountCoordinator.onAuthChanged
        portalAccountCoordinator.onAuthChanged = { [weak focusCloudSyncService] in
            previousAuthChanged?()
            focusCloudSyncService?.scheduleSync(delay: .zero)
            Task { @MainActor [weak focusCloudSyncService] in
                await focusCloudSyncService?.refreshProfile()
            }
        }
    }
}
