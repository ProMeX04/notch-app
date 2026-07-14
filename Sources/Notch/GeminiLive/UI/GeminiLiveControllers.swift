import Foundation

@MainActor
final class GeminiLiveSettingsController {
    let keyStore: GeminiLiveAPIKeyStore
    let backendConfigStore: PortalConfigurationStore
    let settingsStore: GeminiLiveSettingsStore

    init(processInfo: ProcessInfo) {
        keyStore = GeminiLiveAPIKeyStore(processInfo: processInfo)
        backendConfigStore = PortalConfigurationStore(processInfo: processInfo)
        settingsStore = GeminiLiveSettingsStore()
    }
}

@MainActor
final class GeminiLiveAccountController {
    let backendClient: any GeminiLivePortalClient
    let backend: PortalAccountCoordinator

    init(portalAccount: PortalAccountCoordinator, backendClient: any GeminiLivePortalClient) {
        self.backendClient = backendClient
        backend = portalAccount
    }
}

@MainActor
final class GeminiLiveSessionController {
    let session: GeminiLiveSession
    let screenShare = ScreenShareCoordinator()
    let cameraShare = CameraShareCoordinator()

    init(session: GeminiLiveSession) {
        self.session = session
    }
}

@MainActor
final class GeminiLiveToolingController {
    let agentAvatarStore: GeminiAgentAvatarStore
    let userStore: UserStore

    init() {
        agentAvatarStore = GeminiAgentAvatarStore()
        userStore = UserStore()
    }
}
