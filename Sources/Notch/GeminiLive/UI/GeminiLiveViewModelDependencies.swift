import Foundation

@MainActor
struct GeminiLiveViewModelDependencies {
    let entitlementStore: NotchEntitlementStore
    let settingsController: GeminiLiveSettingsController
    let accountController: GeminiLiveAccountController
    let sessionController: GeminiLiveSessionController
    let toolingController: GeminiLiveToolingController
    let userAPIClient: any GeminiLiveUserAPIClient

    static func live(
        entitlementStore: NotchEntitlementStore,
        portalAccount: PortalAccountCoordinator,
        portalClient: any GeminiLivePortalClient,
        processInfo: ProcessInfo = .processInfo,
        session: GeminiLiveSession = GeminiLiveSession(),
        userAPIClient: any GeminiLiveUserAPIClient = URLSessionGeminiLiveUserAPIClient()
    ) -> GeminiLiveViewModelDependencies {
        GeminiLiveViewModelDependencies(
            entitlementStore: entitlementStore,
            settingsController: GeminiLiveSettingsController(processInfo: processInfo),
            accountController: GeminiLiveAccountController(portalAccount: portalAccount, backendClient: portalClient),
            sessionController: GeminiLiveSessionController(session: session),
            toolingController: GeminiLiveToolingController(),
            userAPIClient: userAPIClient
        )
    }
}
