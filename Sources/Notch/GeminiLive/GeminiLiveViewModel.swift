@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
@preconcurrency import ScreenCaptureKit
import Security
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GeminiLiveViewModel: ObservableObject {
    enum TranscriptOverlayMode {
        case hidden
        case autoHide
        case pinned
    }

    @Published private(set) var connectionState: GeminiLiveConnectionState = .disconnected
    @Published private(set) var isMicrophoneEnabled = true {
        didSet { persistSettings() }
    }
    @Published private(set) var inputMode: GeminiLiveInputMode = .openMic {
        didSet { persistSettings() }
    }
    @Published private(set) var isHoldToTalkActive = false
    @Published private(set) var statusText = "Configure Gemini Live to start."
    @Published private(set) var lastErrorMessage: String?
    @Published var selectedConnectionMethod: GeminiLiveConnectionMethod = .userAPIKey {
        didSet {
            persistSettings()
            syncConfiguredConnectionState(updateStatus: !canDisconnectSession)
        }
    }
    @Published private(set) var userTranscript = ""
    @Published private(set) var modelTranscript = ""
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
    @Published private(set) var isModelSpeaking = false
    @Published private(set) var isModelThinking = false
    @Published private(set) var isMicrophoneLive = false
    @Published private(set) var microphoneInputLevel = 0.0
    @Published private(set) var outputVolume = 1.0
    @Published private(set) var holdToTalkShortcut = HoldToTalkShortcutStore.load()
    @Published private(set) var currentContextTokenCount = 0
    @Published private(set) var responseTokenCount = 0
    @Published private(set) var totalTokenCount = 0

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
    @Published var selectedModel: GeminiLiveModel = .flashLivePreview {
        didSet {
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].model = selectedModel.rawValue
            }
            persistSettings()
        }
    }
    @Published var enabledTools: Set<GeminiTool> = [] {
        didSet {
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].enabledTools = enabledTools.map(\.rawValue).sorted()
            }
            persistSettings()
        }
    }
    @Published var enabledSkillNames: Set<String> = [] {
        didSet {
            normalizeEnabledSkillNames()
            if let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) {
                systemPromptPresets[idx].enabledSkillNames = enabledSkillNames.sorted()
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
    @Published private(set) var systemPromptPresets: [GeminiSystemPromptPreset] = GeminiSystemPromptPreset.defaultPresets
    @Published private(set) var selectedSystemPromptID = GeminiSystemPromptPreset.defaultPreset.id
    @Published private(set) var installedSkills: [InstalledSkill] = []
    @Published private(set) var hasSavedAPIKey = false
    @Published private(set) var isSavingAPIKey = false
    @Published private(set) var lastToolAction: ToolActionToast?
    @Published private(set) var overlayInput = TranscriptOverlayInput.idle
    @Published private(set) var isAutoReconnecting = false
    @Published private(set) var reconnectState: GeminiLiveReconnectState = .none
    @Published private(set) var lifecycleState: GeminiLiveLifecycleState = .disconnected
    @Published private(set) var screenShareMode: ScreenShareMode = .fullScreen
    @Published private(set) var isProFromBackend = false
    private var toastClearTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private var lastTalkConnectionAllowed = false
    private var subscriptions = Set<AnyCancellable>()
    private var lastDisconnectWasUserInitiated = false
    private var pendingTurnSeparator = false
    let entitlementStore: NotchEntitlementStore
    let settingsController: GeminiLiveSettingsController
    let accountController: GeminiLiveAccountController
    let sessionController: GeminiLiveSessionController

    private var shouldPreserveMicrophoneLiveStateDuringReconnect: Bool {
        reconnectState.preservesLiveSessionUI && session.isLocalWebRTCMicrophoneCaptureActive
    }
    let toolingController: GeminiLiveToolingController
    private var currentSkillSnapshot: SkillSessionSnapshot?
    private var isNormalizingEnabledSkillNames = false

    private var storedAPIKey: String?
    private var storedBackendConfiguration: GeminiLiveBackendConfiguration?
    var onOpenAppSettingsRequested: (() -> Void)?
    var onExecApprovalAttentionRequested: (() -> Void)?
    @Published private(set) var pendingExecApprovals: [ExecApprovalRequest] = []
    var execApprovals: ExecApprovalCoordinator { toolingController.execApprovals }

    var screenShare: ScreenShareCoordinator { sessionController.screenShare }
    var backend: BackendAccountCoordinator { accountController.backend }
    var session: GeminiLiveSession { sessionController.session }
    private var keyStore: GeminiLiveAPIKeyStore { settingsController.keyStore }
    private var backendConfigStore: GeminiLiveBackendConfigStore { settingsController.backendConfigStore }
    private var backendClient: GeminiLiveBackendClient { accountController.backendClient }
    private var settingsStore: GeminiLiveSettingsStore { settingsController.settingsStore }
    private var agentAvatarStore: GeminiAgentAvatarStore { toolingController.agentAvatarStore }
    private var skillStore: SkillStore { toolingController.skillStore }
    private var skillPackageService: SkillPackageService { toolingController.skillPackageService }
    private var userStore: UserStore { toolingController.userStore }
    private var memoryStore: MemoryStore { toolingController.memoryStore }

    var effectiveConnectionState: GeminiLiveConnectionState {
        lifecycleState.visualConnectionState
    }

    var showsConnectedSessionUI: Bool {
        lifecycleState.preservesSessionUI
    }

    var canDisconnectSession: Bool {
        lifecycleState.canDisconnect
    }

    var canManageConfiguration: Bool {
        lifecycleState.canManageConfiguration
    }

    var canSendLiveInput: Bool {
        lifecycleState.canSendLiveInput
    }

    var isProUser: Bool {
        entitlementStore.isProUser
    }

    var talkPermissionDecision: NotchPermissionDecision {
        entitlementStore.decision(for: .talkConnection)
    }

    init(
        processInfo: ProcessInfo = .processInfo,
        session: GeminiLiveSession = GeminiLiveSession(),
        entitlementStore: NotchEntitlementStore = NotchEntitlementStore()
    ) {
        let settingsController = GeminiLiveSettingsController(processInfo: processInfo)
        let accountController = GeminiLiveAccountController(
            processInfo: processInfo,
            entitlementStore: entitlementStore
        )
        let sessionController = GeminiLiveSessionController(session: session)
        let toolingController = GeminiLiveToolingController()

        self.entitlementStore = entitlementStore
        self.settingsController = settingsController
        self.accountController = accountController
        self.sessionController = sessionController
        self.toolingController = toolingController
        apiKeyText = ""
        backendURLText = GeminiLiveHostedBackend.defaultURL
        backendClientTokenText = ""
        backendAuthEmailText = ""
        installedSkills = toolingController.skillStore.listInstalledSkills()

        let savedSettings = settingsController.settingsStore.read()
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
        }

        userProfileContent = toolingController.userStore.readUserProfile()
        memoryContent = toolingController.memoryStore.readMainMemory()

        let currentGeminiKey = settingsController.keyStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentGeminiKey = (currentGeminiKey?.isEmpty == false) ? currentGeminiKey : nil
        let backend = accountController.backend
        storedAPIKey = normalizedCurrentGeminiKey
        apiKeyText = normalizedCurrentGeminiKey ?? ""
        backendAuthEmailText = backend.authenticatedEmail ?? backend.lastKnownEmail
        backendAuthPhase = backend.authPhase
        backendAuthenticatedEmail = backend.authenticatedEmail
        isBackendAuthenticated = backend.isAuthenticated
        backendSignedInSummary = backend.signedInSummary
        isProFromBackend = backend.isProFromBackend

        if let storedBackend = settingsController.backendConfigStore.read() {
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

        normalizeSystemPromptSelection()
        // Load all per-preset settings without triggering write-through didSets.
        let active = selectedSystemPromptPreset
        _thinkingLevel = Published(initialValue: active.thinkingEnum)
        _selectedVoice = Published(initialValue: active.voiceEnum)
        _selectedModel = Published(initialValue: active.modelEnum)
        _enabledTools = Published(initialValue: active.toolSet)
        _enabledSkillNames = Published(initialValue: Set(active.enabledSkillNames))
        normalizeEnabledSkillNames()
        syncEnabledSkillNamesToActivePreset()
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
                self?.userTranscript = text
                TranscriptSessionLogger.shared.setPendingUserText(text)
                
                let lowerText = text.lowercased()
                if lowerText.contains("tắt mic") || lowerText.contains("stop listening") || lowerText.contains("stop recording") {
                    self?.setMicrophoneEnabled(false)
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

    func openWebAccountSignup() {
        NotchWebPortal.openInBrowser(NotchWebPortal.signupURL(apiBaseURL: configuredBackendConfiguration?.baseURL))
    }

    func openWebAccountLogin() {
        backend.openWebAccountLogin()
    }

    func handleBackendOAuthCallback(_ url: URL) {
        backend.handleOAuthCallbackURL(url)
    }

    func openWebProCheckout() {
        backend.openWebProCheckout()
    }

    /// Refreshes `is_pro` from `GET /auth/me` after web signup, login, or Pro purchase.
    /// Pass `forceRefresh: true` for manual refresh so the app rotates auth/session first.
    func refreshBackendSubscriptionStatus(forceRefresh: Bool = false) async {
        await backend.refreshSubscriptionStatus(forceRefresh: forceRefresh)
    }

    var hasConfiguredAPIKey: Bool {
        hasConfiguredConnection
    }

    var hasConfiguredConnection: Bool {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return configuredAPIKey != nil
        case .managedServer:
            return configuredBackendConfiguration != nil && isBackendAuthenticated
        }
    }

    var requiresAuthenticationForCurrentConnection: Bool {
        selectedConnectionMethod == .managedServer
            && configuredBackendConfiguration != nil
            && !isBackendAuthenticated
    }

    var isBackendAuthRefreshing: Bool {
        backend.isAuthRefreshInFlight
    }

    var backendAuthFailureMessage: String? {
        backend.authPhaseDescription
    }

    var requiresProForCurrentConnection: Bool {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return !talkPermissionDecision.isAllowed
        case .managedServer:
            return isBackendAuthenticated && !talkPermissionDecision.isAllowed
        }
    }

    var canStartConnection: Bool {
        hasConfiguredConnection && !requiresProForCurrentConnection
    }

    var selectedConnectionSetupTitle: String {
        selectedConnectionMethod.setupTitle
    }

    var selectedConnectionSetupDescription: String {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return selectedConnectionMethod.setupDescription
        case .managedServer:
            if configuredBackendConfiguration == nil {
                return "Configure the backend URL first in the Settings tab."
            }
            if requiresAuthenticationForCurrentConnection {
                return "Sign in to your server account in the Settings tab."
            }
            if !talkPermissionDecision.isAllowed {
                return talkPermissionDecision.message
            }
            return "Ready to use your server-managed Gemini session."
        }
    }

    var selectedConnectionManageButtonTitle: String {
        selectedConnectionMethod.manageButtonTitle
    }

    var defaultDisconnectedStatusText: String {
        if requiresAuthenticationForCurrentConnection {
            return "Sign in to your Gemini Live server account."
        }
        if requiresProForCurrentConnection {
            return talkPermissionDecision.message
        }
        return hasConfiguredConnection ? "Ready to connect to Gemini Live." : selectedConnectionMethod.setupDescription
    }

    func openAppSettings() {
        NSApp.activate(ignoringOtherApps: true)
        onOpenAppSettingsRequested?()
    }

    var selectedSystemPromptPreset: GeminiSystemPromptPreset {
        systemPromptPresets.first(where: { $0.id == selectedSystemPromptID })
            ?? systemPromptPresets.first
            ?? GeminiSystemPromptPreset.defaultPreset
    }

    var activeInstalledSkills: [InstalledSkill] {
        installedSkills.filter { enabledSkillNames.contains($0.metadata.name) }
    }

    var userInstalledSkills: [InstalledSkill] {
        installedSkills.filter { $0.metadata.category.lowercased() != "builtin" }
    }

    var effectiveEnabledTools: Set<GeminiTool> {
        enabledTools
    }

    var canManageSkills: Bool {
        canManageConfiguration
    }

    var selectedSystemPromptTitle: String {
        selectedSystemPromptPreset.title
    }

    var selectedSystemPromptAvatarSymbolName: String {
        selectedSystemPromptPreset.resolvedAvatarSymbolName
    }

    var selectedSystemPromptAvatarImageURL: URL? {
        agentAvatarStore.imageURL(for: selectedSystemPromptPreset.avatarImageFilename)
    }

    var canDeleteSelectedSystemPrompt: Bool {
        systemPromptPresets.count > 1
    }

    func selectSystemPrompt(id: String) {
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) else { return }
        guard selectedSystemPromptID != id else { return }
        selectedSystemPromptID = id
        systemPromptPresets[existingIndex].lastUsedAt = Date()
        let active = systemPromptPresets[existingIndex]
        _thinkingLevel = Published(initialValue: active.thinkingEnum)
        _selectedVoice = Published(initialValue: active.voiceEnum)
        _selectedModel = Published(initialValue: active.modelEnum)
        _enabledTools = Published(initialValue: active.toolSet)
        _enabledSkillNames = Published(initialValue: Set(active.enabledSkillNames))
        normalizeEnabledSkillNames()
        syncEnabledSkillNamesToActivePreset()
        persistSettings()
    }

    @discardableResult
    func createSystemPrompt() -> GeminiSystemPromptPreset {
        let preset = GeminiSystemPromptPreset(
            id: UUID().uuidString,
            title: nextDefaultAgentTitle(),
            content: "",
            enabledTools: [],
            voice: GeminiVoice.kore.rawValue,
            model: GeminiLiveModel.flashLivePreview.rawValue,
            thinkingLevel: GeminiThinkingLevel.off.rawValue,
            lastUsedAt: Date()
        )
        systemPromptPresets.append(preset)
        selectedSystemPromptID = preset.id
        _thinkingLevel = Published(initialValue: .off)
        _selectedVoice = Published(initialValue: .kore)
        _selectedModel = Published(initialValue: .flashLivePreview)
        _enabledTools = Published(initialValue: [])
        _enabledSkillNames = Published(initialValue: [])
        persistSettings()
        return preset
    }

    func renameSelectedSystemPrompt(to title: String) {
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? systemPromptPresets[existingIndex].title : trimmedTitle
        guard systemPromptPresets[existingIndex].title != resolvedTitle else { return }
        systemPromptPresets[existingIndex].title = resolvedTitle
        persistSettings()
    }

    func chooseSelectedSystemPromptAvatarImage() {
        guard canManageSkills else { return }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        panel.message = "Choose an image for this agent avatar."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let filename = try agentAvatarStore.saveImage(from: url, presetID: selectedSystemPromptID)
            systemPromptPresets[existingIndex].avatarImageFilename = filename
            persistSettings()
            statusText = "Agent avatar updated."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Avatar update failed."
        }
    }

    func clearSelectedSystemPromptAvatarImage() {
        guard canManageSkills else { return }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        let existingFilename = systemPromptPresets[existingIndex].avatarImageFilename
        guard existingFilename != nil else { return }
        agentAvatarStore.deleteImage(named: existingFilename)
        systemPromptPresets[existingIndex].avatarImageFilename = nil
        persistSettings()
        statusText = "Agent avatar removed."
        lastErrorMessage = nil
    }

    @discardableResult
    func saveSystemPrompt(id: String?, title: String, content: String) -> Bool {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) {
            let resolvedTitle = trimmedTitle.isEmpty ? systemPromptPresets[existingIndex].title : trimmedTitle
            systemPromptPresets[existingIndex].title = resolvedTitle
            systemPromptPresets[existingIndex].content = trimmedContent
            systemPromptPresets[existingIndex].lastUsedAt = Date()
            // Tools are managed separately; don't touch them here.
            selectedSystemPromptID = id
        } else {
            let resolvedTitle = trimmedTitle.isEmpty ? "Agent \(systemPromptPresets.count + 1)" : trimmedTitle
            // New presets start with no tools, default voice, and no thinking.
            let preset = GeminiSystemPromptPreset(
                id: UUID().uuidString,
                title: resolvedTitle,
                content: trimmedContent,
                enabledTools: [],
                voice: GeminiVoice.kore.rawValue,
                model: GeminiLiveModel.flashLivePreview.rawValue,
                thinkingLevel: GeminiThinkingLevel.off.rawValue,
                lastUsedAt: Date()
            )
            systemPromptPresets.append(preset)
            selectedSystemPromptID = preset.id
            _thinkingLevel = Published(initialValue: .off)
            _selectedVoice = Published(initialValue: .kore)
            _selectedModel = Published(initialValue: .flashLivePreview)
            _enabledTools = Published(initialValue: [])
            _enabledSkillNames = Published(initialValue: [])
        }

        normalizeSystemPromptSelection()
        persistSettings()
        return true
    }

    private func nextDefaultAgentTitle() -> String {
        let prefix = "Agent "
        let maxIndex = systemPromptPresets.compactMap { preset -> Int? in
            guard preset.title.hasPrefix(prefix) else { return nil }
            let suffix = preset.title.dropFirst(prefix.count)
            return Int(suffix)
        }
        .max() ?? 0

        return "Agent \(maxIndex + 1)"
    }

    @discardableResult
    func deleteSystemPrompt(id: String) -> Bool {
        guard systemPromptPresets.count > 1 else { return false }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) else { return false }

        agentAvatarStore.deleteImage(named: systemPromptPresets[existingIndex].avatarImageFilename)
        systemPromptPresets.remove(at: existingIndex)
        normalizeSystemPromptSelection()
        persistSettings()
        return true
    }

    @discardableResult
    func deleteSelectedSystemPrompt() -> Bool {
        deleteSystemPrompt(id: selectedSystemPromptID)
    }

    private func normalizeSystemPromptSelection() {
        if systemPromptPresets.isEmpty {
            systemPromptPresets = GeminiSystemPromptPreset.defaultPresets
        }

        if !systemPromptPresets.contains(where: { $0.id == selectedSystemPromptID }) {
            selectedSystemPromptID = systemPromptPresets.first?.id ?? GeminiSystemPromptPreset.defaultPreset.id
        }
    }

    private func buildSystemPrompt(
        activeSkills: [InstalledSkill],
        effectiveTools: Set<GeminiTool>,
        userContent: String,
        memoryContent: String
    ) -> String {
        let promptBody = selectedSystemPromptPreset.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPromptBody = promptBody
        let skillPrompt = SkillPromptComposer.buildPromptSection(
            for: activeSkills,
            canReadSkills: effectiveTools.contains(.read)
        )
        let userPrompt = buildInjectedPromptSection(
            title: "User profile",
            tag: "user",
            content: userContent
        )
        let memoryPrompt = buildInjectedPromptSection(
            title: "Memory",
            tag: "memory",
            content: memoryContent
        )
        let optionalSkillSection = skillPrompt.isEmpty ? "" : "\n\n\(skillPrompt)"
        let optionalUserSection = userPrompt.isEmpty ? "" : "\n\n\(userPrompt)"
        let optionalMemorySection = memoryPrompt.isEmpty ? "" : "\n\n\(memoryPrompt)"
        let toolRules = buildToolRules(for: effectiveTools)
        let optionalToolRulesSection = toolRules.isEmpty ? "" : "\n\nTool rules:\n\(toolRules)"

        return """
        \(resolvedPromptBody)
        \(optionalToolRulesSection)
        \(optionalUserSection)
        \(optionalMemorySection)
        \(optionalSkillSection)
        """
    }

    func saveUserProfile(_ content: String) {
        do {
            try userStore.saveUserProfile(content)
            userProfileContent = content
        } catch {
            lastErrorMessage = "Failed to save user profile."
        }
    }

    func saveMemory(_ content: String) {
        do {
            try memoryStore.saveMemory(content)
            memoryContent = content
        } catch {
            lastErrorMessage = "Failed to save memory."
        }
    }

    private func buildInjectedPromptSection(title: String, tag: String, content: String) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        return """
        \(title):
        <\(tag)>
        \(trimmedContent)
        </\(tag)>
        """
    }

    private func buildToolRules(for effectiveTools: Set<GeminiTool>) -> String {
        var lines: [String] = []

        if effectiveTools.contains(.webSearch) {
            lines.append("- When the user asks for up-to-date information, use the built-in Google Search tool instead of guessing.")
        }
        if effectiveTools.contains(.read) {
            lines.append("- Use `read` to examine files. It supports text files and common images.")
        }
        if effectiveTools.contains(.ls) {
            lines.append("- Use `ls` to inspect one directory quickly. It includes dotfiles and marks directories with `/`.")
        }
        if effectiveTools.contains(.clipboard) {
            lines.append("- Use `clipboard` to read or write the macOS clipboard. Treat clipboard text as potentially sensitive.")
        }
        if effectiveTools.contains(.appControl) {
            lines.append("- Use `appControl` to open, quit, check, minimize, or move macOS app windows. Use exact app names. Do not use for opening URLs.")
        }
        if effectiveTools.contains(.mediaControl) {
            lines.append("- Use `mediaControl` for playback (play, pause, next, previous) and system volume. If no media app is running, say so.")
        }
        if effectiveTools.contains(.pomodoro) {
            lines.append("- Use `pomodoro` to control the Notch Pomodoro timer: start, pause, resume, reset, set durations, check status. If the user says stop/end/cancel focus, call reset.")
        }
        if effectiveTools.contains(.browserControl) {
            lines.append("- Use `browserControl` to open URLs, play music via DuckDuckGo Lucky, or read the current browser tab content.")
        }
        if effectiveTools.contains(.localFileSearch) {
            lines.append("- Use `localFileSearch` to search indexed local files, folders, apps, and media.")
        }
        if effectiveTools.contains(.memory) {
            lines.append("- Use `memory` to read or write persistent USER.md (identity, preferences) and MEMORY.md (durable facts, habits). Use write-user for profile updates and write-memory for broader long-term notes.")
        }
        if effectiveTools.contains(.exec) {
            lines.append("- Use `exec` to run shell commands. Every command requires explicit user approval before execution. Prefer native tools over exec when possible.")
        }

        return lines.joined(separator: "\n")
    }

    private func startedToolAction(for name: String) -> ToolActionToast? {
        switch name {
        case "webSearch":
            return ToolActionToast(label: "Searching web…", icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: "Reading file…", icon: "doc.text", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listing files…", icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: "Using clipboard…", icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: "Controlling app…", icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: "Controlling media…", icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: "Controlling timer…", icon: "timer", showsInOverlay: false)
        case "browserControl":
            return ToolActionToast(label: "Using browser…", icon: "safari", showsInOverlay: false)
        case "localFileSearch":
            return ToolActionToast(label: "Searching files…", icon: "doc.text.magnifyingglass", showsInOverlay: false)
        case "memory":
            return ToolActionToast(label: "Using memory…", icon: "brain", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Running command…", icon: "terminal", showsInOverlay: false)
        default:
            return nil
        }
    }

    private func completedToolAction(for name: String, success: Bool, error: String?, message: String?) -> ToolActionToast? {
        if !success {
            let label = error ?? message ?? failedToolActionLabel(for: name)
            return ToolActionToast(label: label, icon: "exclamationmark.triangle", showsInOverlay: false)
        }

        switch name {
        case "webSearch":
            return ToolActionToast(label: "Web search", icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: "Read file", icon: "doc.text", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listed files", icon: "list.bullet", showsInOverlay: false)
        case "clipboard":
            return ToolActionToast(label: "Clipboard", icon: "doc.on.clipboard", showsInOverlay: false)
        case "appControl":
            return ToolActionToast(label: "App controlled", icon: "macwindow", showsInOverlay: false)
        case "mediaControl":
            return ToolActionToast(label: "Media controlled", icon: "playpause", showsInOverlay: false)
        case "pomodoro":
            return ToolActionToast(label: "Timer controlled", icon: "timer", showsInOverlay: false)
        case "browserControl":
            return ToolActionToast(label: "Browser action", icon: "safari", showsInOverlay: false)
        case "localFileSearch":
            return ToolActionToast(label: "File search", icon: "doc.text.magnifyingglass", showsInOverlay: false)
        case "memory":
            return ToolActionToast(label: "Memory updated", icon: "brain", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Command executed", icon: "terminal", showsInOverlay: false)
        default:
            return nil
        }
    }

    private func failedToolActionLabel(for name: String) -> String {
        switch name {
        case "read":
            return "Read failed."
        case "ls":
            return "List failed."
        case "webSearch":
            return "Web search failed."
        case "clipboard":
            return "Clipboard failed."
        case "appControl":
            return "App control failed."
        case "mediaControl":
            return "Media control failed."
        case "pomodoro":
            return "Timer control failed."
        case "browserControl":
            return "Browser control failed."
        case "localFileSearch":
            return "File search failed."
        case "memory":
            return "Memory failed."
        case "exec":
            return "Command failed."
        default:
            return "Tool failed."
        }
    }

    func postToolAction(
        label: String,
        icon: String,
        showsInOverlay: Bool = true,
        autoClearAfter: TimeInterval? = 3
    ) {
        toastClearTask?.cancel()
        lastToolAction = ToolActionToast(label: label, icon: icon, showsInOverlay: showsInOverlay)

        guard let autoClearAfter else { return }

        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(autoClearAfter))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self?.lastToolAction = nil
            }
        }
    }

    var connectionButtonTitle: String {
        switch effectiveConnectionState {
        case .connected:
            return "Disconnect"
        case .connecting:
            return "Cancel"
        case .disconnected, .failed:
            return "Connect"
        }
    }

    var connectionButtonIcon: String {
        switch effectiveConnectionState {
        case .connected:
            return "xmark.circle.fill"
        case .connecting:
            return "stop.circle.fill"
        case .disconnected, .failed:
            return "play.circle.fill"
        }
    }

    var microphoneButtonTitle: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive ? "Release to Send" : "Hold to Talk"
        }
        return isMicrophoneEnabled ? "Mute Mic" : "Unmute Mic"
    }

    var microphoneButtonIcon: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive ? "mic.circle.fill" : "mic"
        }
        return isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
    }

    var canToggleMicrophone: Bool {
        canDisconnectSession
    }

    var showCompactIndicator: Bool {
        switch effectiveConnectionState {
        case .connecting, .connected:
            return true
        case .failed, .disconnected:
            return false
        }
    }

    var compactAccentColor: NSColor {
        effectiveConnectionState.accentColor
    }

    var screenSharingLabel: String { isWindowScreenSharing ? "App" : isRegionScreenSharing ? "Region" : "Screen" }

    var screenSharingIcon: String { isWindowScreenSharing ? "macwindow" : isRegionScreenSharing ? "crop" : (isScreenSharingEnabled ? "eye.fill" : "eye") }

    var isRegionScreenSharing: Bool { isScreenSharingEnabled && screenShareMode == .selectedRegion }

    var isWindowScreenSharing: Bool { isScreenSharingEnabled && screenShareMode == .appWindow }

    var isCompactIndicatorAnimated: Bool {
        isActivelyListening
    }

    var holdToTalkReadyText: String {
        "Hold \(holdToTalkShortcut.displayString) to talk."
    }

    var connectedMicStatusText: String {
        if inputMode == .pushToTalk {
            return isHoldToTalkActive
                ? (isMicrophoneLive ? "Listening… Release to send." : pendingMicrophoneStatusText)
                : holdToTalkReadyText
        }
        guard isMicrophoneEnabled else { return "Microphone is muted." }
        return isMicrophoneLive ? "Microphone is live." : pendingMicrophoneStatusText
    }

    var pendingMicrophoneStatusText: String {
        "Starting microphone..."
    }

    var effectiveMicrophoneEnabled: Bool {
        switch inputMode {
        case .openMic:
            return isMicrophoneEnabled
        case .pushToTalk:
            return isHoldToTalkActive
        }
    }

    var isActivelyListening: Bool {
        canSendLiveInput && effectiveMicrophoneEnabled && isMicrophoneLive
    }

    var connectedPlaceholderText: String {
        if reconnectState.preservesLiveSessionUI {
            return statusText
        }
        return isActivelyListening ? "Gemini is listening..." : connectedMicStatusText
    }

    var shouldShowMicrophoneReadinessHint: Bool {
        showsConnectedSessionUI && effectiveMicrophoneEnabled && !isMicrophoneLive
    }

    var microphoneReadinessHintText: String {
        if reconnectState.preservesLiveSessionUI {
            return "Microphone will be ready after Gemini reconnects."
        }
        return "Microphone is not ready yet. Wait a moment before talking."
    }

    var microphoneReadinessHintIcon: String {
        reconnectState.preservesLiveSessionUI ? "mic.badge.clock.fill" : "mic.slash.circle.fill"
    }

    var compactMicrophoneReadinessIcon: String {
        reconnectState.preservesLiveSessionUI ? "mic.badge.clock.fill" : "mic.slash.circle.fill"
    }

    func toggleConnection() {
        if canDisconnectSession {
            disconnect()
        } else {
            connect()
        }
    }

    func connectIfNeeded() {
        guard !canDisconnectSession else { return }
        connect()
    }

    func disconnectIfNeeded() {
        guard canDisconnectSession else { return }
        disconnect()
    }

    func saveBackendConfiguration() async -> Bool {
        guard let draftBackendURL else {
            lastErrorMessage = "Gemini Live server URL is missing."
            statusText = "Enter the Gemini Live server URL, then save again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Testing Gemini Live server..."
        defer { isSavingAPIKey = false }

        do {
            guard
                let normalizedURL = URL(string: draftBackendURL),
                let scheme = normalizedURL.scheme,
                !scheme.isEmpty,
                normalizedURL.host != nil
            else {
                throw GeminiLiveBackendError.invalidBaseURL
            }

            let normalizedConfiguration = GeminiLiveBackendConfiguration(
                baseURL: normalizedURL.path.isEmpty ? normalizedURL.appendingPathComponent("") : normalizedURL,
                clientToken: draftBackendClientToken,
                userAccessToken: backend.currentAccessToken
            )
            do {
                try await backendClient.validate(configuration: normalizedConfiguration)
            } catch GeminiLiveBackendError.unauthorized {
                guard backendConfigStore.save(
                    baseURLString: normalizedConfiguration.displayURL,
                    clientToken: normalizedConfiguration.clientToken
                ) else {
                    lastErrorMessage = "Couldn't save the Gemini Live server configuration."
                    statusText = "Gemini Live server validation passed, but saving failed."
                    return false
                }

                storedBackendConfiguration = GeminiLiveBackendConfiguration(
                    baseURL: normalizedConfiguration.baseURL,
                    clientToken: normalizedConfiguration.clientToken,
                    userAccessToken: nil
                )
                backendURLText = normalizedConfiguration.displayURL
                backendClientTokenText = normalizedConfiguration.clientToken ?? ""
                lastErrorMessage = nil
                statusText = "Gemini Live server saved. Sign in to continue."
                syncConfiguredConnectionState()
                return true
            }

            guard backendConfigStore.save(
                baseURLString: normalizedConfiguration.displayURL,
                clientToken: normalizedConfiguration.clientToken
            ) else {
                lastErrorMessage = "Couldn't save the Gemini Live server configuration."
                statusText = "Gemini Live server validation passed, but saving failed."
                return false
            }

            storedBackendConfiguration = normalizedConfiguration
            backendURLText = normalizedConfiguration.displayURL
            backendClientTokenText = normalizedConfiguration.clientToken ?? ""
            lastErrorMessage = nil
            statusText = "Gemini Live server saved."
            syncConfiguredConnectionState()
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Gemini Live server test failed."
            return false
        }
    }

    func saveAPIKey() async -> Bool {
        guard let draftAPIKey else {
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Enter your Gemini API key, then save again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Testing Gemini API key..."
        defer { isSavingAPIKey = false }

        do {
            try await validateAPIKey(draftAPIKey)

            guard keyStore.save(draftAPIKey) else {
                lastErrorMessage = keyStore.saveFailureMessage
                statusText = "Gemini API key test passed, but saving failed."
                return false
            }

            storedAPIKey = draftAPIKey
            apiKeyText = draftAPIKey
            lastErrorMessage = nil
            statusText = keyStore.saveSuccessMessage
            syncConfiguredConnectionState()
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Gemini API key test failed."
            return false
        }
    }

    func logoutBackendAccount() async {
        await backend.logout()
        backendAuthPasswordText = ""
    }

    func connect(clearingTranscripts: Bool = true) {
        if reconnectState != .fullRestart {
            setReconnectState(.none)
        }

        guard hasConfiguredConnection else {
            setConnectionState(.failed)
            lastErrorMessage = selectedConnectionMethod == .userAPIKey
                ? "Gemini API key is missing."
                : (configuredBackendConfiguration == nil
                    ? "Gemini Live server is missing."
                    : "Please sign in to your Gemini Live server account.")
            statusText = defaultDisconnectedStatusText
            logConnectBlocked(reason: "missing configuration")
            handleUnrecoverableReconnectFailureIfNeeded()
            return
        }

        if requiresAuthenticationForCurrentConnection {
            setConnectionState(.failed)
            lastErrorMessage = "Please sign in to your Gemini Live server account."
            statusText = defaultDisconnectedStatusText
            logConnectBlocked(reason: "managed server auth missing")
            handleUnrecoverableReconnectFailureIfNeeded()
            return
        }

        let talkDecision = talkPermissionDecision
        if !talkDecision.isAllowed {
            setConnectionState(.failed)
            lastErrorMessage = talkDecision.message
            statusText = defaultDisconnectedStatusText
            logConnectBlocked(reason: "Talk requires Pro")
            handleUnrecoverableReconnectFailureIfNeeded()
            return
        }

        if clearingTranscripts {
            clearTranscripts()
            TranscriptSessionLogger.shared.startSession()
        }
        lastDisconnectWasUserInitiated = false
        setConnectionState(.connecting)
        if !shouldPreserveMicrophoneLiveStateDuringReconnect {
            isMicrophoneLive = false
            microphoneInputLevel = 0
        }
        lastErrorMessage = nil
        statusText = "Connecting to Gemini Live..."
        logConnectAttempt(clearingTranscripts: clearingTranscripts)

        Task { @MainActor in
            let skillSnapshot: SkillSessionSnapshot
            if clearingTranscripts || self.currentSkillSnapshot == nil {
                skillSnapshot = self.makeSkillSessionSnapshot()
                self.currentSkillSnapshot = skillSnapshot
            } else {
                skillSnapshot = self.currentSkillSnapshot ?? self.makeSkillSessionSnapshot()
            }

            let systemPrompt = self.buildSystemPrompt(
                activeSkills: skillSnapshot.activeSkills,
                effectiveTools: skillSnapshot.effectiveTools,
                userContent: self.userProfileContent,
                memoryContent: self.memoryContent
            )

            let preset = self.selectedSystemPromptPreset
            let systemInstruction = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingConfiguration = !clearingTranscripts ? self.session.currentConfiguration : nil
            let connectionCredential: String
            let restAPIKey: String?
            let backendConfiguration: GeminiLiveBackendConfiguration?

            if let existingConfiguration,
               !self.shouldRefreshManagedServerCredential(existingConfiguration) {
                connectionCredential = existingConfiguration.connectionCredential
                restAPIKey = existingConfiguration.restAPIKey
                backendConfiguration = existingConfiguration.backendConfiguration
            } else {
                switch self.selectedConnectionMethod {
                case .managedServer:
                    guard let configuredBackend = await self.backend.freshConfiguredBackendUserConfiguration() else {
                        self.setConnectionState(.failed)
                        self.lastErrorMessage = self.configuredBackendConfiguration == nil
                            ? "Gemini Live server is missing."
                            : "Please sign in to your Gemini Live server account."
                        self.statusText = self.defaultDisconnectedStatusText
                        self.logConnectBlocked(reason: "managed server auth missing")
                        self.handleUnrecoverableReconnectFailureIfNeeded()
                        return
                    }

                    self.statusText = "Requesting secure Gemini Live token..."
                    do {
                        let token = try await self.requestManagedServerSessionToken(
                            configuration: configuredBackend,
                            model: preset.modelEnum.apiName,
                            systemInstruction: systemInstruction.isEmpty ? nil : systemInstruction,
                            voiceName: preset.voiceEnum.apiName,
                            thinkingBudget: preset.thinkingEnum.budget > 0 ? preset.thinkingEnum.budget : nil
                        )
                        connectionCredential = token.name
                        restAPIKey = nil
                        backendConfiguration = configuredBackend
                    } catch {
                        if self.backend.shouldClearBackendAuthSession(for: error) {
                            self.logGeminiFailure(
                                "session token request rejected the saved session; clearing local auth",
                                error: error
                            )
                            self.backend.clearBackendAuthSession()
                        } else {
                            self.logGeminiFailure("session token request failed", error: error)
                        }
                        self.setConnectionState(.failed)
                        self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        self.statusText = "Couldn't create a Gemini Live session token."
                        if self.reconnectState == .fullRestart {
                            _ = self.scheduleReconnect()
                        }
                        return
                    }
                case .userAPIKey:
                    guard let configuredAPIKey = self.configuredAPIKey else {
                        self.setConnectionState(.failed)
                        self.lastErrorMessage = "Gemini API key is missing."
                        self.statusText = self.defaultDisconnectedStatusText
                        self.logConnectBlocked(reason: "API key missing")
                        self.handleUnrecoverableReconnectFailureIfNeeded()
                        return
                    }
                    connectionCredential = configuredAPIKey
                    restAPIKey = configuredAPIKey
                    backendConfiguration = nil
                }
            }

            self.session.connect(
                connectionCredential: connectionCredential,
                restAPIKey: restAPIKey,
                backendConfiguration: backendConfiguration,
                model: preset.modelEnum.apiName,
                systemPrompt: systemPrompt,
                microphoneEnabled: self.effectiveMicrophoneEnabled && self.hasMicrophonePermission,
                microphonePrewarmingEnabled: self.inputMode == .pushToTalk,
                thinkingBudget: preset.thinkingEnum.budget,
                voiceName: preset.voiceEnum.apiName,
                enabledTools: skillSnapshot.effectiveTools,
                skillSnapshot: skillSnapshot,
                resumeSession: !clearingTranscripts
            )
            self.syncEffectiveMicrophoneState()
        }
    }

    private func requestManagedServerSessionToken(
        configuration: GeminiLiveBackendConfiguration,
        model: String,
        systemInstruction: String?,
        voiceName: String,
        thinkingBudget: Int?
    ) async throws -> GeminiLiveEphemeralTokenResponse {
        try await backendClient.createSessionToken(
            configuration: configuration,
            requestBody: GeminiLiveSessionTokenRequest(
                model: model,
                systemInstruction: systemInstruction,
                voiceName: voiceName,
                thinkingBudget: thinkingBudget,
                responseModalities: ["AUDIO"]
            )
        )
    }

    func disconnect() {
        lastDisconnectWasUserInitiated = true
        cancelReconnect()
        screenShare.stop()
        execApprovals.clearAll()
        toastClearTask = nil
        lastToolAction = nil
        isModelThinking = false
        isHoldToTalkActive = false
        isMicrophoneLive = false
        // Transcript có thể rất dài; giữ lại sau khi ngắt kết nối làm RAM không giảm trong Activity Monitor.
        clearTranscripts()
        currentSkillSnapshot = nil
        session.disconnect(userInitiated: true)
        setConnectionState(.disconnected)
        statusText = defaultDisconnectedStatusText
        TranscriptSessionLogger.shared.endSession()
    }

    @discardableResult
    private func scheduleReconnect() -> Bool {
        guard reconnectTask == nil else { return true }
        guard reconnectAttempt < maxReconnectAttempts else {
            handleUnrecoverableReconnectFailure(statusText: "Connection lost. Please reconnect manually.")
            return false
        }
        reconnectAttempt += 1
        setReconnectState(.fullRestart)
        statusText = "Reconnecting... (attempt \(reconnectAttempt)/\(maxReconnectAttempts))"

        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.lastDisconnectWasUserInitiated = false
            self.connect(clearingTranscripts: false)
        }
        return true
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        setReconnectState(.none)
    }

    func startFullScreenSharing() {
        screenShare.startFullScreen()
    }

    func startRegionScreenSharing() {
        screenShare.startRegion()
    }

    func startWindowSharing() {
        screenShare.startWindow()
    }

    func stopScreenSharing() {
        screenShare.stop()
    }

    func toggleMicrophone() {
        switch inputMode {
        case .openMic:
            setOpenMicrophoneEnabled(!isMicrophoneEnabled)
        case .pushToTalk:
            isHoldToTalkActive ? endHoldToTalk() : beginHoldToTalk()
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        switch inputMode {
        case .openMic:
            setOpenMicrophoneEnabled(enabled)
        case .pushToTalk:
            enabled ? beginHoldToTalk() : endHoldToTalk()
        }
    }

    func setInputMode(_ mode: GeminiLiveInputMode) {
        guard inputMode != mode else { return }
        inputMode = mode

        if mode == .openMic {
            isHoldToTalkActive = false
            isMicrophoneEnabled = true
        } else {
            isHoldToTalkActive = false
            isMicrophoneEnabled = false
        }

        syncEffectiveMicrophoneState()
        if canSendLiveInput {
            statusText = connectedMicStatusText
        }
    }

    private var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func ensureMicrophonePermission(completion: @escaping @Sendable (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            requestMicrophoneAccess(completion: completion)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func setOpenMicrophoneEnabled(_ enabled: Bool) {
        guard isMicrophoneEnabled != enabled else { return }
        isMicrophoneEnabled = enabled
        guard inputMode == .openMic else { return }
        syncEffectiveMicrophoneState()
        if canSendLiveInput {
            statusText = connectedMicStatusText
        }
    }

    func beginHoldToTalk() {
        guard inputMode == .pushToTalk else { return }
        guard canSendLiveInput else { return }
        guard !isHoldToTalkActive else { return }
        isHoldToTalkActive = true
        isModelSpeaking = false
        session.interruptModelPlayback()
        syncEffectiveMicrophoneState()
        statusText = connectedMicStatusText
    }

    func endHoldToTalk() {
        guard inputMode == .pushToTalk else { return }
        guard isHoldToTalkActive else { return }
        isHoldToTalkActive = false
        syncEffectiveMicrophoneState()
        session.resumeModelPlayback()
        if canSendLiveInput {
            statusText = holdToTalkReadyText
        }
    }

    func setOutputVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        guard abs(outputVolume - clamped) > 0.001 else { return }
        outputVolume = clamped
        session.setOutputVolume(clamped)
        persistSettings()
    }

    func setTranscriptOverlayEnabled(_ enabled: Bool) {
        guard showTranscriptOverlay != enabled else { return }
        showTranscriptOverlay = enabled
        statusText = showTranscriptOverlay ? "Captions enabled." : "Captions hidden."
    }

    var transcriptOverlayMode: TranscriptOverlayMode {
        if !showTranscriptOverlay {
            return .hidden
        }
        return transcriptOverlayAutoHide ? .autoHide : .pinned
    }

    /// Sends typed text over the Live socket as `realtimeInput.text` (required for Gemini 3.1 Flash Live during conversation).
    @discardableResult
    func sendLiveChatMessage(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard canSendLiveInput else { return false }
        session.sendClientTextTurn(trimmed)
        userTranscript = trimmed
        isModelThinking = true
        TranscriptSessionLogger.shared.recordUserText(trimmed)
        GeminiLiveChatHistoryStore.shared.save(trimmed)
        return true
    }

    func clearTranscripts() {
        userTranscript = ""
        modelTranscript = ""
        pendingTurnSeparator = false
        isModelThinking = false
        isModelSpeaking = false
        lastErrorMessage = nil
    }

    func shutdown() {
        disconnect()
        execApprovals.clearAll()
        subscriptions.removeAll()
        backend.shutdown()
        screenShare.stop()
    }

    func importSkill() {
        guard canManageSkills else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "skill") ?? .zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Import"
        panel.message = "Choose a .skill package or a folder containing SKILL.md."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let installed: InstalledSkill
            do {
                installed = try skillPackageService.importSkillSource(from: url)
            } catch SkillImportError.duplicateSkill(let name) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Replace existing skill?"
                alert.informativeText = "A skill named \"\(name)\" is already installed. Replace it with this package?"
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                installed = try skillPackageService.importSkillSource(from: url, replacingExisting: true)
            }

            reloadInstalledSkills()
            enabledSkillNames.insert(installed.metadata.name)
            statusText = "Imported skill \"\(installed.metadata.name)\"."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Skill import failed."
        }
    }

    func deleteSkill(named name: String) {
        guard canManageSkills else { return }


        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete skill?"
        alert.informativeText = "Delete \"\(name)\" from Notch? This removes the skill package from your Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try skillStore.deleteSkill(named: name)
            for i in systemPromptPresets.indices {
                systemPromptPresets[i].enabledSkillNames.removeAll { $0 == name }
            }
            enabledSkillNames.remove(name)
            reloadInstalledSkills()
            statusText = "Deleted skill \"\(name)\"."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Couldn't delete skill \"\(name)\": \(error.localizedDescription)"
            statusText = "Skill deletion failed."
        }
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

    private func persistSettings() {
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
                selectedSystemPromptID: selectedSystemPromptID
            )
        )
    }

    private func syncEffectiveMicrophoneState() {
        guard canDisconnectSession else { return }
        session.setMicrophonePrewarmingEnabled(inputMode == .pushToTalk)
        
        let desiredState = effectiveMicrophoneEnabled
        guard desiredState else {
            session.setMicrophoneEnabled(false)
            return
        }

        ensureMicrophonePermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    self.session.setMicrophoneEnabled(true)
                } else {
                    // If denied, we revert the local state
                    if self.inputMode == .openMic {
                        self.isMicrophoneEnabled = false
                    } else {
                        self.isHoldToTalkActive = false
                    }
                    self.lastErrorMessage = "Microphone access is required for Gemini Live."
                    self.statusText = "Enable microphone access for Notch in System Settings."
                    NotchLog.gemini.error("Microphone permission denied after lazy request")
                    self.syncEffectiveMicrophoneState() // Sync the reverted state to the session
                }
            }
        }
    }

    private func setConnectionState(_ state: GeminiLiveConnectionState) {
        connectionState = state
        recomputeLifecycleState()
    }

    private func setReconnectState(_ state: GeminiLiveReconnectState) {
        reconnectState = state
        isAutoReconnecting = state != .none
        recomputeLifecycleState()
    }

    private func recomputeLifecycleState() {
        if reconnectState != .none {
            lifecycleState = .reconnecting(reconnectState)
            return
        }

        switch connectionState {
        case .disconnected:
            lifecycleState = .disconnected
        case .connecting:
            lifecycleState = .connecting
        case .connected:
            lifecycleState = .live
        case .failed:
            lifecycleState = .failed
        }
    }

    private func handleUnrecoverableReconnectFailureIfNeeded() {
        guard reconnectState == .fullRestart else { return }
        handleUnrecoverableReconnectFailure(statusText: statusText)
    }

    private func handleUnrecoverableReconnectFailure(statusText: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        setReconnectState(.none)
        setConnectionState(.failed)
        self.statusText = statusText
        isHoldToTalkActive = false
        isModelThinking = false
        // Always tear down a possibly-preserved audio session here. The previous
        // guard `session.isLocalWebRTCMicrophoneCaptureActive` checked whether the
        // microphone was *currently capturing*, but the audio session is preserved
        // on transport failure based on `hadCompletedSetup && captureMode == .webRTC`
        // alone (see GeminiLiveSession.handleSocketTransportFailure). When the user
        // had mic muted or was in PTT idle, the guard would skip teardown and leak
        // outputEngine / webRTCAudioIO. `stopPreservedAudioSession` is idempotent.
        session.stopPreservedAudioSession()
        isMicrophoneLive = false
        microphoneInputLevel = 0
    }

    private func reloadInstalledSkills() {
        installedSkills = skillStore.listInstalledSkills()
        normalizeEnabledSkillNames()
    }

    private func makeSkillSessionSnapshot() -> SkillSessionSnapshot {
        let skillsByName = Dictionary(uniqueKeysWithValues: activeInstalledSkills.map { ($0.metadata.name, $0) })
        let enabledNames = activeInstalledSkills.map(\.metadata.name).sorted()
        return SkillSessionSnapshot(
            skillsByName: skillsByName,
            enabledSkillNames: enabledNames,
            effectiveTools: effectiveEnabledTools
        )
    }

    private func normalizeEnabledSkillNames() {
        guard !isNormalizingEnabledSkillNames else { return }
        isNormalizingEnabledSkillNames = true
        defer { isNormalizingEnabledSkillNames = false }

        let validNames = Set(installedSkills.map(\.metadata.name))
        let filtered = enabledSkillNames.intersection(validNames)
        if filtered != enabledSkillNames {
            enabledSkillNames = filtered
        }
    }

    private func syncEnabledSkillNamesToActivePreset() {
        guard let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        systemPromptPresets[idx].enabledSkillNames = enabledSkillNames.sorted()
    }

    private var draftBackendURL: String? {
        let trimmedInput = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var draftBackendAuthEmail: String? {
        let trimmedInput = backendAuthEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var draftBackendAuthPassword: String? {
        let trimmedInput = backendAuthPasswordText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var draftAPIKey: String? {
        let trimmedInput = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var draftBackendClientToken: String? {
        let trimmedInput = backendClientTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var configuredBackendConfiguration: GeminiLiveBackendConfiguration? {
        storedBackendConfiguration ?? backendConfigStore.read()
    }

    private var needsBackendConfigurationSave: Bool {
        guard let draftBackendURL else { return configuredBackendConfiguration == nil }
        guard let configuration = configuredBackendConfiguration else { return true }

        return configuration.displayURL != draftBackendURL
            || configuration.clientToken != draftBackendClientToken
    }

    private var configuredAPIKey: String? {
        currentStoredGeminiKey()
    }

    private func currentStoredGeminiKey() -> String? {
        normalizedStoredSecret(storedAPIKey ?? keyStore.read())
    }

    private func syncConfiguredConnectionState(updateStatus: Bool = false) {
        hasSavedAPIKey = hasConfiguredConnection
        guard updateStatus else { return }
        statusText = defaultDisconnectedStatusText
    }

    private func ensureBackendConfigurationForAuth() async -> GeminiLiveBackendConfiguration? {
        backendURLText = GeminiLiveHostedBackend.defaultURL
        backendClientTokenText = ""

        if needsBackendConfigurationSave {
            let didSave = await saveBackendConfiguration()
            guard didSave else { return nil }
        }

        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: nil
        )
    }

    private func logConnectAttempt(clearingTranscripts: Bool) {
        NotchLog.gemini.notice(
            "Connect requested: method=\(self.selectedConnectionMethod.rawValue, privacy: .public) auth=\(self.isBackendAuthenticated, privacy: .public) pro=\(self.isProUser, privacy: .public) clearingTranscripts=\(clearingTranscripts, privacy: .public)"
        )
    }

    private func logConnectBlocked(reason: String) {
        NotchLog.gemini.notice(
            "Connect blocked: reason=\(reason, privacy: .public) method=\(self.selectedConnectionMethod.rawValue, privacy: .public) auth=\(self.isBackendAuthenticated, privacy: .public) pro=\(self.isProUser, privacy: .public)"
        )
    }

    private func logGeminiFailure(_ summary: String, error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        NotchLog.gemini.error("\(summary, privacy: .public): \(message, privacy: .public)")
    }

    private func shouldRefreshManagedServerCredential(_ configuration: LiveSessionConfiguration) -> Bool {
        configuration.backendConfiguration != nil && configuration.connectionCredential.hasPrefix("auth_tokens/")
    }

    private func normalizedStoredSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validateAPIKey(_ apiKey: String) async throws {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIKeyValidationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data),
               !apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiAPIKeyValidationError.server(apiError.error.message)
            }
            throw GeminiAPIKeyValidationError.server("Gemini returned HTTP \(httpResponse.statusCode) while testing the API key.")
        }
    }

    private struct GeminiAPIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    private enum GeminiAPIKeyValidationError: LocalizedError {
        case invalidRequest
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Couldn't prepare the Gemini API key test."
            case .invalidResponse:
                return "Gemini returned an invalid response while testing the API key."
            case let .server(message):
                return message
            }
        }
    }

    private func requestMicrophoneAccess(completion: @escaping @Sendable (Bool) -> Void) {
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
