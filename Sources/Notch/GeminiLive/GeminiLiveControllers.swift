import Foundation

@MainActor
final class GeminiLiveSettingsController {
    let keyStore: GeminiLiveAPIKeyStore
    let backendConfigStore: GeminiLiveBackendConfigStore
    let settingsStore: GeminiLiveSettingsStore

    init(processInfo: ProcessInfo) {
        keyStore = GeminiLiveAPIKeyStore(processInfo: processInfo)
        backendConfigStore = GeminiLiveBackendConfigStore(processInfo: processInfo)
        settingsStore = GeminiLiveSettingsStore()
    }
}

@MainActor
final class GeminiLiveAccountController {
    let backendClient: GeminiLiveBackendClient
    let backend: BackendAccountCoordinator

    init(
        processInfo: ProcessInfo,
        entitlementStore: NotchEntitlementStore
    ) {
        let backendConfigStore = GeminiLiveBackendConfigStore(processInfo: processInfo)
        let backendAuthStore = GeminiLiveBackendAuthStore(processInfo: processInfo)
        backendClient = GeminiLiveBackendClient()
        backend = BackendAccountCoordinator(
            client: backendClient,
            configStore: backendConfigStore,
            authStore: backendAuthStore,
            entitlementStore: entitlementStore
        )
    }
}

@MainActor
final class GeminiLiveSessionController {
    let session: GeminiLiveSession
    let screenShare = ScreenShareCoordinator()

    init(session: GeminiLiveSession) {
        self.session = session
    }
}

@MainActor
final class GeminiLiveToolingController {
    let execApprovals: ExecApprovalCoordinator
    let agentAvatarStore: GeminiAgentAvatarStore
    let skillStore: SkillStore
    let skillPackageService: SkillPackageService
    let userStore: UserStore
    let memoryStore: MemoryStore

    init() {
        let execApprovalStore = GeminiLiveExecApprovalStore()
        execApprovals = ExecApprovalCoordinator(store: execApprovalStore)
        agentAvatarStore = GeminiAgentAvatarStore()
        skillStore = SkillStore()
        skillPackageService = SkillPackageService(skillStore: skillStore)
        userStore = UserStore()
        memoryStore = MemoryStore()
    }
}
