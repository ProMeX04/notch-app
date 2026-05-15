import Foundation

@MainActor
struct GeminiLiveViewModelDependencies {
    let entitlementStore: NotchEntitlementStore
    let settingsController: GeminiLiveSettingsController
    let accountController: GeminiLiveAccountController
    let sessionController: GeminiLiveSessionController
    let toolingController: GeminiLiveToolingController

    static func live(
        entitlementStore: NotchEntitlementStore,
        processInfo: ProcessInfo = .processInfo,
        session: GeminiLiveSession = GeminiLiveSession()
    ) -> GeminiLiveViewModelDependencies {
        GeminiLiveViewModelDependencies(
            entitlementStore: entitlementStore,
            settingsController: GeminiLiveSettingsController(processInfo: processInfo),
            accountController: GeminiLiveAccountController(
                processInfo: processInfo,
                entitlementStore: entitlementStore
            ),
            sessionController: GeminiLiveSessionController(session: session),
            toolingController: GeminiLiveToolingController()
        )
    }
}
