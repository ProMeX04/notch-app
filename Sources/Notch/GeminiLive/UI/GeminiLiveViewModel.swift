@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import NotchChatHistoryCore
import NotchGeminiLiveCore
@preconcurrency import ScreenCaptureKit
import Security
import SwiftUI
import NotchGeminiSkillStorage

@MainActor
final class GeminiLiveViewModel: ObservableObject {
    enum TranscriptOverlayMode {
        case hidden
        case autoHide
        case pinned
    }

    @Published var connectionState: GeminiLiveConnectionState = .disconnected
    @Published var isMicrophoneEnabled = true {
        didSet { persistSettings() }
    }
    @Published var inputMode: GeminiLiveInputMode = .openMic {
        didSet { persistSettings() }
    }
    @Published var isHoldToTalkActive = false
    @Published var statusText = "Configure Gemini Live to start."
    @Published var lastErrorMessage: String?
    @Published var selectedConnectionMethod: GeminiLiveConnectionMethod = .userAPIKey {
        didSet {
            persistSettings()
            syncConfiguredConnectionState(updateStatus: !canDisconnectSession)
        }
    }
    @Published var userTranscript = ""
    @Published var modelTranscript = ""
    @Published var apiKeyText: String
    @Published var backendURLText: String
    @Published var backendClientTokenText: String
    @Published var backendAuthEmailText: String
    @Published var backendAuthPasswordText: String = ""
    @Published private(set) var backendAuthPhase: BackendAuthPhase = .signedOut
    @Published private(set) var backendAuthenticatedEmail: String?
    @Published private(set) var isBackendAuthenticated = false {
        didSet {
            syncConfiguredConnectionState()
        }
    }
    @Published private(set) var backendSignedInSummary: String?
    @Published var userProfileContent: String = ""
    @Published var memoryContent: String = ""

    @Published private(set) var isScreenSharingEnabled = false
    @Published var isModelSpeaking = false
    @Published var isModelThinking = false
    @Published var isMicrophoneLive = false
    @Published var microphoneInputLevel = 0.0
    @Published var outputVolume = 1.0
    @Published private(set) var holdToTalkShortcut = HoldToTalkShortcutStore.load()
    @Published private(set) var currentContextTokenCount = 0
    @Published private(set) var responseTokenCount = 0
    @Published private(set) var totalTokenCount = 0
    @Published var userTurnSequence = 0

    // Per-preset: reading reflects the active preset; writing updates that preset and persists.
    @Published var thinkingLevel: GeminiThinkingLevel = .off {
        didSet {
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].thinkingLevel = thinkingLevel.rawValue
            }
            persistSettings()
        }
    }
    @Published var selectedVoice: GeminiVoice = .kore {
        didSet {
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].voice = selectedVoice.rawValue
            }
            persistSettings()
        }
    }
    @Published var selectedModelID: String = GeminiLiveModel.defaultModelID {
        didSet {
            let normalizedID = GeminiLiveModel.normalizedModelID(selectedModelID)
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].model = normalizedID
            }
            persistSettings()
        }
    }
    @Published var availableLiveModels: [GeminiLiveModel] = [] {
        didSet { persistSettings() }
    }
    @Published var isRefreshingLiveModels = false
    @Published var lastLiveModelRefreshMessage: String?
    @Published var enabledTools: Set<GeminiTool> = [] {
        didSet {
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].enabledTools = enabledTools.map(\.rawValue).sorted()
            }
            persistSettings()
        }
    }
    @Published var enabledSkillIDs: Set<String> = [] {
        didSet {
            normalizeEnabledSkillIDs()
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].enabledSkillIDs = enabledSkillIDs.sorted()
                systemPromptPresets[idx].enabledSkillNames = []
            }
            persistSettings()
        }
    }
    @Published var showTranscriptOverlay: Bool = true {
        didSet { persistSettings() }
    }
    /// When true, the floating transcript overlay fades out shortly after the model stops speaking.
    @Published var transcriptOverlayAutoHide: Bool = true {
        didSet { persistSettings() }
    }
    @Published var showLiveChatInput: Bool = true {
        didSet { persistSettings() }
    }
    @Published var systemPromptPresets: [GeminiSystemPromptPreset] = GeminiSystemPromptPreset.defaultPresets
    @Published var selectedSystemPromptID = GeminiSystemPromptPreset.defaultPreset.id
    @Published var installedSkills: [InstalledSkill] = []
    @Published var hasSavedAPIKey = false
    @Published var isSavingAPIKey = false
    @Published var lastToolAction: ToolActionToast?
    @Published private(set) var overlayInput = TranscriptOverlayInput.idle
    @Published var isAutoReconnecting = false
    @Published var reconnectState: GeminiLiveReconnectState = .none
    @Published var lifecycleState: GeminiLiveLifecycleState = .disconnected
    @Published private(set) var screenShareMode: ScreenShareMode = .fullScreen
    @Published private(set) var isProFromBackend = false
    var toastClearTask: Task<Void, Never>?
    var reconnectTask: Task<Void, Never>?
    var reconnectAttempt = 0
    let maxReconnectAttempts = 3
    private var lastTalkConnectionAllowed = false
    private var subscriptions = Set<AnyCancellable>()
    var lastDisconnectWasUserInitiated = false
    var pendingTurnSeparator = false
    let entitlementStore: NotchEntitlementStore
    let settingsController: GeminiLiveSettingsController
    let accountController: GeminiLiveAccountController
    let sessionController: GeminiLiveSessionController

    var shouldPreserveMicrophoneLiveStateDuringReconnect: Bool {
        reconnectState.preservesLiveSessionUI && session.isLocalWebRTCMicrophoneCaptureActive
    }
    let toolingController: GeminiLiveToolingController
    var currentSkillSnapshot: SkillSessionSnapshot?
    var isNormalizingEnabledSkillIDs = false

    var storedAPIKey: String?
    var storedBackendConfiguration: GeminiLiveBackendConfiguration?
    var onOpenAppSettingsRequested: (() -> Void)?
    var onExecApprovalAttentionRequested: (() -> Void)?
    @Published private(set) var pendingExecApprovals: [ExecApprovalRequest] = []
    var execApprovals: ExecApprovalCoordinator { toolingController.execApprovals }

    var screenShare: ScreenShareCoordinator { sessionController.screenShare }
    var backend: BackendAccountCoordinator { accountController.backend }
    var session: GeminiLiveSession { sessionController.session }
    var keyStore: GeminiLiveAPIKeyStore { settingsController.keyStore }
    var backendConfigStore: GeminiLiveBackendConfigStore { settingsController.backendConfigStore }
    var backendClient: GeminiLiveBackendClient { accountController.backendClient }
    private var settingsStore: GeminiLiveSettingsStore { settingsController.settingsStore }
    var agentAvatarStore: GeminiAgentAvatarStore { toolingController.agentAvatarStore }
    private var skillStore: SkillStore { toolingController.skillStore }
    var skillsRepository: GeminiSkillsRepository { toolingController.skillsRepository }
    var userStore: UserStore { toolingController.userStore }
    var memoryStore: MemoryStore { toolingController.memoryStore }
    var selectedModel: GeminiLiveModel {
        get {
            let normalizedID = GeminiLiveModel.normalizedModelID(selectedModelID)
            return availableLiveModels.first { $0.apiName == normalizedID }
                ?? GeminiLiveModel(id: normalizedID)
        }
        set {
            selectedModelID = GeminiLiveModel.normalizedModelID(newValue.apiName)
        }
    }

    init(dependencies: GeminiLiveViewModelDependencies) {
        self.entitlementStore = dependencies.entitlementStore
        self.settingsController = dependencies.settingsController
        self.accountController = dependencies.accountController
        self.sessionController = dependencies.sessionController
        self.toolingController = dependencies.toolingController
        apiKeyText = ""
        backendURLText = GeminiLiveHostedBackend.defaultURL
        backendClientTokenText = ""
        backendAuthEmailText = ""
        installedSkills = (try? dependencies.toolingController.skillsRepository.listInstalledSkillsSorted()) ?? []

        let savedSettings = dependencies.settingsController.settingsStore.read()
        if let savedSettings {
            isMicrophoneEnabled = savedSettings.isMicrophoneEnabled
            inputMode = savedSettings.inputMode
            showTranscriptOverlay = savedSettings.showTranscriptOverlay
            transcriptOverlayAutoHide = savedSettings.transcriptOverlayAutoHide
            showLiveChatInput = savedSettings.showLiveChatInput
            outputVolume = min(max(savedSettings.outputVolume, 0), 1)
            selectedConnectionMethod = savedSettings.connectionMethod
            systemPromptPresets = savedSettings.systemPromptPresets
            selectedSystemPromptID = savedSettings.selectedSystemPromptID
            availableLiveModels = savedSettings.availableLiveModels
        }

        userProfileContent = dependencies.toolingController.userStore.readUserProfile()
        memoryContent = dependencies.toolingController.memoryStore.readMainMemory()

        let currentGeminiKey = dependencies.settingsController.keyStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentGeminiKey = (currentGeminiKey?.isEmpty == false) ? currentGeminiKey : nil
        let backend = dependencies.accountController.backend
        storedAPIKey = normalizedCurrentGeminiKey
        apiKeyText = normalizedCurrentGeminiKey ?? ""
        backendAuthEmailText = backend.authenticatedEmail ?? backend.lastKnownEmail
        backendAuthPhase = backend.authPhase
        backendAuthenticatedEmail = backend.authenticatedEmail
        isBackendAuthenticated = backend.isAuthenticated
        backendSignedInSummary = backend.signedInSummary
        isProFromBackend = backend.isProFromBackend

        if let storedBackend = dependencies.settingsController.backendConfigStore.read() {
            storedBackendConfiguration = storedBackend
            backendURLText = GeminiLiveHostedBackend.defaultURL
            backendClientTokenText = ""
        } else {
            backendURLText = GeminiLiveHostedBackend.defaultURL
            backendClientTokenText = ""
        }

        if savedSettings == nil, normalizedCurrentGeminiKey == nil {
            selectedConnectionMethod = .managedServer
        }

        recomputeProEntitlement()
        syncConfiguredConnectionState(updateStatus: true)

        migrateEnabledSkillsFromLegacyPresetFieldsIfNeeded()
        normalizeSystemPromptSelection()
        session.setOutputVolume(outputVolume)
        execApprovals.$pending.assign(to: &$pendingExecApprovals)
        execApprovals.onApprove = { [weak self] toolCallID in
            self?.session.approveExecCall(toolCallID: toolCallID)
        }
        execApprovals.onDeny = { [weak self] toolCallID in
            self?.session.denyExecCall(toolCallID: toolCallID)
        }
        backend.$authPhase.assign(to: &$backendAuthPhase)
        backend.$isAuthenticated.assign(to: &$isBackendAuthenticated)
        backend.$signedInSummary.assign(to: &$backendSignedInSummary)
        backend.$authenticatedEmail.assign(to: &$backendAuthenticatedEmail)
        backend.$isProFromBackend.assign(to: &$isProFromBackend)
        entitlementStore.$snapshot
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                self.recomputeProEntitlement()
            }
            .store(in: &subscriptions)
        backend.onAuthChanged = { [weak self] in
            self?.syncConfiguredConnectionState()
        }
        backend.onProChanged = { [weak self] _ in
            self?.recomputeProEntitlement()
        }
        backend.onStatusChange = { [weak self] message in
            guard let self, let message else { return }
            self.statusText = message
        }
        backend.onErrorChange = { [weak self] message in
            self?.lastErrorMessage = message
        }
        backend.onSavingStateChange = { [weak self] isSaving in
            self?.isSavingAPIKey = isSaving
        }
        backend.onAuthEmailChange = { [weak self] email in
            self?.backendAuthEmailText = email
        }
        backend.currentDraftEmailProvider = { [weak self] in
            self?.draftBackendAuthEmail
        }
        backend.ensureConfigurationForAuth = { [weak self] in
            await self?.ensureBackendConfigurationForAuth()
        }
        backend.currentConfigurationProvider = { [weak self] in
            self?.configuredBackendConfiguration
        }
        backend.shouldDisconnectManagedSession = { [weak self] in
            guard let self else { return false }
            return self.selectedConnectionMethod == .managedServer
                && self.canDisconnectSession
        }
        backend.disconnectManagedSession = { [weak self] in
            self?.disconnect()
        }
        screenShare.$isActive.assign(to: &$isScreenSharingEnabled)
        screenShare.$mode.assign(to: &$screenShareMode)
        screenShare.onFrameCaptured = { [weak self] data in
            self?.session.sendScreenFrame(data)
        }
        screenShare.onStatusChange = { [weak self] message in
            guard let self, let message else { return }
            self.statusText = message
        }
        screenShare.onErrorMessageChange = { [weak self] message in
            self?.lastErrorMessage = message
        }
        screenShare.connectionStateProvider = { [weak self] in
            self?.effectiveConnectionState ?? .disconnected
        }

        session.onReconnectStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.setReconnectState(state)
            }
        }

        session.onStateChange = { [weak self] state, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setConnectionState(state)
                if state != .connected {
                    self.isHoldToTalkActive = false
                    if !self.shouldPreserveMicrophoneLiveStateDuringReconnect {
                        self.isMicrophoneLive = false
                        self.microphoneInputLevel = 0
                    }
                    self.isModelThinking = false
                }
                if let message, !message.isEmpty {
                    if state == .connected, (message == "Gemini Live is ready." || message == "Gemini Live resumed.") {
                        self.statusText = self.connectedMicStatusText
                    } else {
                        self.statusText = message
                    }
                } else {
                    self.statusText = self.defaultDisconnectedStatusText
                }

                // Auto-reconnect on unexpected failure
                if state == .failed && !self.lastDisconnectWasUserInitiated {
                    switch self.reconnectState {
                    case .transport, .sessionRefresh:
                        break
                    case .none, .fullRestart:
                        _ = self.scheduleReconnect()
                    }
                } else if state == .connected {
                    // Only cancel a *view-model* level reconnect task. A session-level
                    // transport/sessionRefresh reconnect emits a preview .connected
                    // (preserveConnectedState) BEFORE the new socket is actually live;
                    // resetting reconnectState here would flip lifecycleState back to
                    // .live too early and re-enable chat input while socketTask is nil,
                    // silently dropping the user's message.
                    if self.reconnectState == .fullRestart {
                        self.cancelReconnect()
                    }
                } else if state == .disconnected {
                    self.cancelReconnect()
                }
            }
        }

        session.onUserTranscript = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   text != self.userTranscript {
                    self.userTurnSequence += 1
                }
                self.userTranscript = text
                TranscriptSessionLogger.shared.setPendingUserText(text)
                
                let lowerText = text.lowercased()
                if lowerText.contains("tắt mic") || lowerText.contains("stop listening") || lowerText.contains("stop recording") {
                    self.setMicrophoneEnabled(false)
                }
            }
        }

        session.onModelThinkingStateChange = { [weak self] isThinking in
            DispatchQueue.main.async {
                self?.isModelThinking = isThinking
                if isThinking {
                    // User finished talking; commit their voice transcript before model output.
                    TranscriptSessionLogger.shared.flushUserIfPending()
                }
            }
        }

        session.onModelTranscript = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isModelThinking = false
                self.isModelSpeaking = true
                let isNewTurn = self.modelTranscript.isEmpty || self.pendingTurnSeparator
                if self.modelTranscript.isEmpty {
                    self.modelTranscript = text
                } else if self.pendingTurnSeparator {
                    self.modelTranscript = text
                    self.pendingTurnSeparator = false
                } else {
                    self.modelTranscript += " " + text
                }

                // Prevent unbounded string growth in exceptionally long continuous responses
                if self.modelTranscript.count > 10_000 {
                    self.modelTranscript = String(self.modelTranscript.suffix(8_000))
                }

                // Logger keeps its own un-truncated buffer so very long turns are still saved in full.
                TranscriptSessionLogger.shared.appendModelChunk(text, isNewTurn: isNewTurn)
            }
        }

        session.onTurnComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isModelThinking = false
                self.isModelSpeaking = false
                if !self.modelTranscript.isEmpty {
                    self.pendingTurnSeparator = true
                }
                TranscriptSessionLogger.shared.flushModelTurn()
            }
        }

        session.onMicrophoneInputLevel = { [weak self] level in
            DispatchQueue.main.async {
                guard let self else { return }
                let clamped = min(max(level, 0), 1)
                let smoothed = (self.microphoneInputLevel * 0.55) + (clamped * 0.45)
                // Only update if the change is visually meaningful to avoid View invalidate storms
                guard abs(smoothed - self.microphoneInputLevel) > 0.02 else { return }
                self.microphoneInputLevel = smoothed
            }
        }

        session.onMicrophoneCaptureStateChange = { [weak self] isLive in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMicrophoneLive = isLive

                guard self.canSendLiveInput else { return }
                guard self.statusText == self.connectedMicStatusText || self.statusText == self.pendingMicrophoneStatusText else {
                    return
                }
                self.statusText = self.connectedMicStatusText
            }
        }

        session.onUsageMetadata = { [weak self] usage in
            DispatchQueue.main.async {
                guard let self else { return }
                let hasReportedTokens =
                    usage.currentContextTokenCount > 0 ||
                    usage.responseTokenCount > 0 ||
                    usage.totalTokenCount > 0

                if hasReportedTokens {
                    let reportedContextTokenCount = max(
                        usage.currentContextTokenCount,
                        usage.promptTokenCount,
                        usage.totalTokenCount
                    )

                    if reportedContextTokenCount > 0 {
                        self.currentContextTokenCount = max(self.currentContextTokenCount, reportedContextTokenCount)
                    }
                    if usage.responseTokenCount > 0 {
                        self.responseTokenCount = max(self.responseTokenCount, usage.responseTokenCount)
                    }
                    if usage.totalTokenCount > 0 {
                        self.totalTokenCount = max(self.totalTokenCount, usage.totalTokenCount)
                    }
                    return
                }

                if !self.showsConnectedSessionUI {
                    self.currentContextTokenCount = 0
                    self.responseTokenCount = 0
                    self.totalTokenCount = 0
                }
            }
        }

        session.onFunctionStarted = { [weak self] name, _ in
            DispatchQueue.main.async {
                guard let self, let toast = self.startedToolAction(for: name) else { return }
                self.isModelThinking = false
                self.postToolAction(
                    label: toast.label,
                    icon: toast.icon,
                    showsInOverlay: toast.showsInOverlay,
                    autoClearAfter: nil
                )
            }
        }

        session.onFunctionExecuted = { [weak self] name, args, result in
            let resultSuccess = result["success"] as? Bool
            let resultError = result["error"] as? String
            let resultMessage = result["message"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                if let toast = self.completedToolAction(
                    for: name,
                    success: resultSuccess == true,
                    error: resultError,
                    message: resultMessage
                ) {
                    self.postToolAction(
                        label: toast.label,
                        icon: toast.icon,
                        showsInOverlay: toast.showsInOverlay
                    )
                } else {
                    self.toastClearTask?.cancel()
                    self.toastClearTask = nil
                    self.lastToolAction = nil
                }
            }
        }
        
        configureExecApprovalCallbacks()
        configureSkillWriterCallbacks()

        // Derive overlayInput from all relevant publishers so observers subscribe to one source.
        Publishers.CombineLatest(
            Publishers.CombineLatest3($userTranscript, $modelTranscript, $isModelSpeaking),
            Publishers.CombineLatest(
                $lastToolAction,
                Publishers.CombineLatest3($showTranscriptOverlay, $connectionState, $reconnectState)
            )
        )
        .map { transcripts, rest in
            let toolAction = rest.0
            let (subsOn, state, reconnectState) = rest.1
            return TranscriptOverlayInput(
                userText: transcripts.0,
                modelText: transcripts.1,
                isModelSpeaking: transcripts.2,
                toolAction: toolAction.flatMap { $0.showsInOverlay ? $0 : nil },
                subsEnabled: subsOn,
                isConnected: state == .connected || state == .connecting || reconnectState.preservesLiveSessionUI
            )
        }
        .assign(to: &$overlayInput)

        NotificationCenter.default.publisher(for: HoldToTalkShortcutStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.holdToTalkShortcut = HoldToTalkShortcutStore.load()
                if self.canSendLiveInput && !self.isHoldToTalkActive {
                    self.statusText = self.holdToTalkReadyText
                }
            }
            .store(in: &subscriptions)

        recomputeProEntitlement()

        persistSettings()

        Task { [weak self] in
            await self?.refreshBackendSubscriptionStatus()
        }

        Task { [weak self] in
            await self?.refreshLiveModelsOnLaunchIfPossible()
        }
    }

    private func recomputeProEntitlement() {
        let wasAllowed = lastTalkConnectionAllowed
        let isAllowed = talkPermissionDecision.isAllowed
        lastTalkConnectionAllowed = isAllowed

        guard wasAllowed && !isAllowed else {
            syncConfiguredConnectionState(updateStatus: true)
            return
        }

        if canDisconnectSession {
            disconnect()
        } else {
            syncConfiguredConnectionState(updateStatus: true)
        }
    }

    func openAppSettings() {
        NSApp.activate(ignoringOtherApps: true)
        onOpenAppSettingsRequested?()
    }

    func shutdown() {
        disconnect()
        execApprovals.clearAll()
        subscriptions.removeAll()
        backend.shutdown()
        screenShare.stop()
    }

    func reloadKeyDrafts() {
        let currentBackendConfiguration = backendConfigStore.read()
        storedBackendConfiguration = currentBackendConfiguration
        backendURLText = currentBackendConfiguration?.displayURL ?? ""
        backendClientTokenText = currentBackendConfiguration?.clientToken ?? ""

        let currentGeminiKey = currentStoredGeminiKey()
        storedAPIKey = currentGeminiKey
        apiKeyText = currentGeminiKey ?? ""
        backend.reloadCurrentAuth()
        backendAuthEmailText = backend.authenticatedEmail ?? backend.lastKnownEmail
        syncConfiguredConnectionState(updateStatus: !canDisconnectSession)
    }

    func persistSettings() {
        settingsStore.save(
            GeminiLiveSettings(
                isMicrophoneEnabled: isMicrophoneEnabled,
                inputMode: inputMode,
                showTranscriptOverlay: showTranscriptOverlay,
                transcriptOverlayAutoHide: transcriptOverlayAutoHide,
                showLiveChatInput: showLiveChatInput,
                outputVolume: outputVolume,
                connectionMethod: selectedConnectionMethod,
                systemPromptPresets: systemPromptPresets,
                selectedSystemPromptID: selectedSystemPromptID,
                availableLiveModels: availableLiveModels
            )
        )
    }

    func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}
