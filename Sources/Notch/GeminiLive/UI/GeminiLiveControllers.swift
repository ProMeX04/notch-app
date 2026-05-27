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
    let execApprovals: ExecApprovalCoordinator
    let agentAvatarStore: GeminiAgentAvatarStore
    let skillStore: SkillStore
    let skillsRepository: GeminiSkillsRepository
    let userStore: UserStore
    let memoryStore: MemoryStore

    init() {
        let execApprovalStore = GeminiLiveExecApprovalStore()
        execApprovals = ExecApprovalCoordinator(store: execApprovalStore)
        agentAvatarStore = GeminiAgentAvatarStore()
        skillStore = SkillStore()
        skillsRepository = GeminiSkillsRepository()
        userStore = UserStore()
        memoryStore = MemoryStore()
    }
}
