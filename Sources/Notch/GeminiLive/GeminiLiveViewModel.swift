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
    enum ScreenShareMode {
        case fullScreen
        case selectedRegion
        case appWindow
    }

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
            syncConfiguredConnectionState(updateStatus: connectionState != .connected && connectionState != .connecting)
        }
    }
    @Published private(set) var userTranscript = ""
    @Published private(set) var modelTranscript = ""
    @Published var apiKeyText: String
    @Published var backendURLText: String
    @Published var backendClientTokenText: String
    @Published var backendAuthEmailText: String
    @Published var backendAuthPasswordText: String = ""
    @Published private(set) var backendAuthenticatedEmail: String?
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
    @Published private(set) var pendingExecApprovals: [ExecApprovalRequest] = []
    /// True when the user has Pro via the backend (`is_pro`) or dev bypass.
    @Published private(set) var isProUser = false
    private var isProFromBackend = false
    private var toastClearTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private var subscriptions = Set<AnyCancellable>()
    private var lastDisconnectWasUserInitiated = false
    private var pendingTurnSeparator = false
    private var screenCaptureTask: Task<Void, Never>?
    private let screenRegionSelectionController = ScreenRegionSelectionController()
    private let windowShareSelectionController = WindowShareSelectionController()
    private let screenShareHighlightController = ScreenShareHighlightController()
    private var screenShareMode: ScreenShareMode = .fullScreen
    private var screenShareRegion: CGRect?
    private var screenShareFilter: SCContentFilter?
    private let session: GeminiLiveSession
    private let keyStore: GeminiLiveAPIKeyStore
    private let backendConfigStore: GeminiLiveBackendConfigStore
    private let backendAuthStore: GeminiLiveBackendAuthStore
    private let backendClient: GeminiLiveBackendClient
    private let settingsStore: GeminiLiveSettingsStore
    private let execApprovalStore: GeminiLiveExecApprovalStore
    private let agentAvatarStore: GeminiAgentAvatarStore
    private let skillStore: SkillStore
    private let skillPackageService: SkillPackageService
    private let userStore: UserStore
    private let memoryStore: MemoryStore
    private var currentSkillSnapshot: SkillSessionSnapshot?
    private var isNormalizingEnabledSkillNames = false

    private var storedAPIKey: String?
    private var storedBackendConfiguration: GeminiLiveBackendConfiguration?
    private var storedBackendAuthSession: GeminiLiveBackendAuthSession?
    private var backendAuthRefreshTask: Task<GeminiLiveBackendAuthSession, Error>?
    var onExecApprovalAttentionRequested: (() -> Void)?
    var onOpenAppSettingsRequested: (() -> Void)?

    var currentPendingExecApproval: ExecApprovalRequest? {
        pendingExecApprovals.first
    }

    init(processInfo: ProcessInfo = .processInfo, session: GeminiLiveSession = GeminiLiveSession()) {
        self.session = session
        keyStore = GeminiLiveAPIKeyStore(processInfo: processInfo)
        backendConfigStore = GeminiLiveBackendConfigStore(processInfo: processInfo)
        backendAuthStore = GeminiLiveBackendAuthStore(processInfo: processInfo)
        backendClient = GeminiLiveBackendClient()
        settingsStore = GeminiLiveSettingsStore()
        execApprovalStore = GeminiLiveExecApprovalStore()
        agentAvatarStore = GeminiAgentAvatarStore()
        skillStore = SkillStore()
        skillPackageService = SkillPackageService(skillStore: skillStore)
        userStore = UserStore()
        memoryStore = MemoryStore()
        installedSkills = skillStore.listInstalledSkills()

        let savedSettings = settingsStore.read()
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

        userProfileContent = userStore.readUserProfile()
        memoryContent = memoryStore.readMainMemory()

        let currentGeminiKey = keyStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentGeminiKey = (currentGeminiKey?.isEmpty == false) ? currentGeminiKey : nil
        storedAPIKey = normalizedCurrentGeminiKey
        apiKeyText = normalizedCurrentGeminiKey ?? ""
        let backendAuthSession = backendAuthStore.read()
        storedBackendAuthSession = backendAuthSession
        backendAuthEmailText = backendAuthSession?.user.email ?? backendAuthStore.readLastEmail()
        backendAuthenticatedEmail = backendAuthSession?.user.email

        if let storedBackend = backendConfigStore.read() {
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

        session.onStateChange = { [weak self] state, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.connectionState = state
                if state != .connected {
                    self.isHoldToTalkActive = false
                    self.isMicrophoneLive = false
                    self.microphoneInputLevel = 0
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
                    self.scheduleReconnect()
                } else if state == .connected {
                    // A successful session-level reconnect must cancel any pending
                    // view-model reconnect task, otherwise it will fire later and
                    // start a fresh connect loop on top of the recovered session.
                    self.cancelReconnect()
                }
            }
        }

        session.onUserTranscript = { [weak self] text in
            DispatchQueue.main.async {
                self?.userTranscript = text
            }
        }

        session.onModelThinkingStateChange = { [weak self] isThinking in
            DispatchQueue.main.async {
                self?.isModelThinking = isThinking
            }
        }

        session.onModelTranscript = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isModelThinking = false
                self.isModelSpeaking = true
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

                guard self.connectionState == .connected else { return }
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

                if self.connectionState != .connected {
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

        session.onShouldAutoApproveExec = { [execApprovalStore] command, workingDirectory in
            execApprovalStore.isApproved(command: command, workingDirectory: workingDirectory)
        }

        session.onExecApprovalRequested = { [weak self] request in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.pendingExecApprovals.contains(where: { $0.toolCallID == request.toolCallID }) {
                    self.pendingExecApprovals.append(request)
                }
                self.postToolAction(
                    label: "Command approval needed",
                    icon: "terminal",
                    showsInOverlay: false,
                    autoClearAfter: nil
                )
                self.onExecApprovalAttentionRequested?()
            }
        }

        // Derive overlayInput from all relevant publishers so observers subscribe to one source.
        Publishers.CombineLatest(
            Publishers.CombineLatest3($userTranscript, $modelTranscript, $isModelSpeaking),
            Publishers.CombineLatest(
                $lastToolAction,
                Publishers.CombineLatest($showTranscriptOverlay, $connectionState)
            )
        )
        .map { transcripts, rest in
            let toolAction = rest.0
            let (subsOn, state) = rest.1
            return TranscriptOverlayInput(
                userText: transcripts.0,
                modelText: transcripts.1,
                isModelSpeaking: transcripts.2,
                toolAction: toolAction.flatMap { $0.showsInOverlay ? $0 : nil },
                subsEnabled: subsOn,
                isConnected: state == .connected || state == .connecting
            )
        }
        .assign(to: &$overlayInput)

        NotificationCenter.default.publisher(for: HoldToTalkShortcutStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.holdToTalkShortcut = HoldToTalkShortcutStore.load()
                if self.connectionState == .connected && !self.isHoldToTalkActive {
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
        isProUser = NotchProEntitlement.isProUser(backendPro: isProFromBackend)
    }

    func openWebAccountSignup() {
        NotchWebPortal.openInBrowser(NotchWebPortal.signupURL())
    }

    func openWebAccountLogin() {
        NotchWebPortal.openInBrowser(NotchWebPortal.loginURL())
    }

    func openWebProCheckout() {
        Task {
            guard let configuration = await self.freshConfiguredBackendUserConfiguration() else {
                NotchWebPortal.openInBrowser(NotchWebPortal.proCheckoutURL())
                return
            }

            do {
                let bridge = try await backendClient.createWebBridgeToken(configuration: configuration)
                let url = NotchWebPortal.authBridgeURL(token: bridge.bridgeToken)
                NotchWebPortal.openInBrowser(url)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
                NotchWebPortal.openInBrowser(NotchWebPortal.proCheckoutURL())
            }
        }
    }

    /// Refreshes `is_pro` from `GET /auth/me` after web signup, login, or Pro purchase.
    func refreshBackendSubscriptionStatus() async {
        guard let configuration = await freshConfiguredBackendUserConfiguration() else {
            isProFromBackend = false
            recomputeProEntitlement()
            return
        }

        do {
            let user = try await backendClient.me(configuration: configuration)
            isProFromBackend = user.isPro ?? false
            recomputeProEntitlement()
        } catch {
            if shouldClearBackendAuthSession(for: error) {
                logGeminiFailure(
                    "subscription status refresh rejected the saved session; clearing local auth",
                    error: error
                )
                clearBackendAuthSession()
                return
            }
            logGeminiFailure("subscription status refresh failed; keeping previous Pro state", error: error)
            // Keep previous backend Pro flag if the request fails (offline, etc.).
        }
    }

    var hasConfiguredAPIKey: Bool {
        hasConfiguredConnection
    }

    var hasConfiguredConnection: Bool {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return configuredAPIKey != nil
        case .managedServer:
            return configuredBackendConfiguration != nil && backendAuthorizationToken != nil
        }
    }

    var requiresProForCurrentConnection: Bool {
        selectedConnectionMethod == .managedServer && hasConfiguredConnection && !isProUser
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
            if backendAuthorizationToken == nil {
                return "Sign in to your server account in the Settings tab."
            }
            if !isProUser {
                return "Notch Pro is required before you can connect with your Notch account."
            }
            return "Ready to use your server-managed Gemini session."
        }
    }

    var selectedConnectionManageButtonTitle: String {
        selectedConnectionMethod.manageButtonTitle
    }

    var isBackendAuthenticated: Bool {
        storedBackendAuthSession != nil
    }

    var backendSignedInSummary: String? {
        backendAuthenticatedEmail
    }

    var defaultDisconnectedStatusText: String {
        if requiresProForCurrentConnection {
            return "Notch Pro is required to use the hosted Gemini Live server."
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
        connectionState != .connecting && connectionState != .connected
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
        if effectiveTools.contains(.exec) {
            lines.append("- Use `exec` for local shell commands on this Mac, such as `curl`, `python3`, `jq`, or `git`. Commands default to `~/.notch/workspace`, and new commands may require approval.")
        }
        if effectiveTools.contains(.read) {
            lines.append("- Use `read` to examine files instead of `cat` or `sed`. It supports text files and common images, and uses `offset`/`limit` for large files.")
        }
        if effectiveTools.contains(.write) {
            lines.append("- Use `write` to create or overwrite text files inside `~/.notch/workspace`. Store stable user identity details in `USER.md` and broader durable notes in `MEMORY.md`.")
        }
        if effectiveTools.contains(.ls) {
            lines.append("- Use `ls` to inspect one directory quickly before guessing paths. It includes dotfiles and marks directories with `/`.")
        }
        if effectiveTools.contains(.find) {
            lines.append("- Use `find` with glob patterns like `*.ts` or `src/**/*.json` when you need to locate files before reading or editing them.")
        }
        if effectiveTools.contains(.grep) {
            lines.append("- Use `grep` to search file contents before guessing where text lives.")
        }
        if effectiveTools.contains(.edit) {
            lines.append("- Use `edit` for exact text replacements in one file, including multiple disjoint changes via `edits[]`, instead of rewriting the whole file.")
        }

        return lines.joined(separator: "\n")
    }

    private func startedToolAction(for name: String) -> ToolActionToast? {
        switch name {
        case "webSearch":
            return ToolActionToast(label: "Searching web…", icon: "magnifyingglass", showsInOverlay: false)
        case "read":
            return ToolActionToast(label: "Reading file…", icon: "doc.text", showsInOverlay: false)
        case "write":
            return ToolActionToast(label: "Writing file…", icon: "square.and.pencil", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listing files…", icon: "list.bullet", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Running command…", icon: "terminal", showsInOverlay: false)
        case "find":
            return ToolActionToast(label: "Finding files…", icon: "folder", showsInOverlay: false)
        case "grep":
            return ToolActionToast(label: "Searching files…", icon: "text.magnifyingglass", showsInOverlay: false)
        case "edit":
            return ToolActionToast(label: "Editing file…", icon: "slider.horizontal.below.rectangle", showsInOverlay: false)
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
        case "write":
            return ToolActionToast(label: "Wrote file", icon: "square.and.pencil", showsInOverlay: false)
        case "ls":
            return ToolActionToast(label: "Listed files", icon: "list.bullet", showsInOverlay: false)
        case "exec":
            return ToolActionToast(label: "Ran command", icon: "terminal", showsInOverlay: false)
        case "find":
            return ToolActionToast(label: "Found files", icon: "folder", showsInOverlay: false)
        case "grep":
            return ToolActionToast(label: "Searched files", icon: "text.magnifyingglass", showsInOverlay: false)
        case "edit":
            return ToolActionToast(label: "Edited file", icon: "slider.horizontal.below.rectangle", showsInOverlay: false)
        default:
            return nil
        }
    }

    private func failedToolActionLabel(for name: String) -> String {
        switch name {
        case "exec":
            return "Command failed."
        case "read":
            return "Read failed."
        case "write":
            return "Write failed."
        case "ls":
            return "List failed."
        case "find":
            return "Find failed."
        case "grep":
            return "Search failed."
        case "edit":
            return "Edit failed."
        case "webSearch":
            return "Web search failed."
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
        switch connectionState {
        case .connected:
            return "Disconnect"
        case .connecting:
            return "Cancel"
        case .disconnected, .failed:
            return "Connect"
        }
    }

    var connectionButtonIcon: String {
        switch connectionState {
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
        connectionState == .connected
    }

    var showCompactIndicator: Bool {
        switch connectionState {
        case .connecting, .connected:
            return true
        case .failed, .disconnected:
            return false
        }
    }

    var compactAccentColor: NSColor {
        connectionState.accentColor
    }

    var screenSharingLabel: String {
        if isWindowScreenSharing {
            return "App"
        }
        return isRegionScreenSharing ? "Region" : "Screen"
    }

    var screenSharingIcon: String {
        if isWindowScreenSharing {
            return "macwindow"
        }
        if isRegionScreenSharing {
            return "crop"
        }
        return isScreenSharingEnabled ? "eye.fill" : "eye"
    }

    var isRegionScreenSharing: Bool {
        isScreenSharingEnabled && screenShareMode == .selectedRegion
    }

    var isWindowScreenSharing: Bool {
        isScreenSharingEnabled && screenShareMode == .appWindow
    }

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
        connectionState == .connected && effectiveMicrophoneEnabled && isMicrophoneLive
    }

    var connectedPlaceholderText: String {
        isActivelyListening ? "Gemini is listening..." : connectedMicStatusText
    }

    func toggleConnection() {
        switch connectionState {
        case .connected, .connecting:
            disconnect()
        case .disconnected, .failed:
            connect()
        }
    }

    func connectIfNeeded() {
        guard connectionState != .connected, connectionState != .connecting else { return }
        connect()
    }

    func disconnectIfNeeded() {
        guard connectionState == .connected || connectionState == .connecting else { return }
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
                userAccessToken: storedBackendAuthSession?.accessToken
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

    func signupBackendAccount() async -> Bool {
        guard let configuration = await ensureBackendConfigurationForAuth() else {
            lastErrorMessage = "Gemini Live server URL is missing."
            statusText = "Check the connection and try again."
            return false
        }
        guard let email = draftBackendAuthEmail else {
            lastErrorMessage = "Email is missing."
            statusText = "Enter your email, then try again."
            return false
        }
        guard let password = draftBackendAuthPassword else {
            lastErrorMessage = "Password is missing."
            statusText = "Enter your password, then try again."
            return false
        }
        guard password.count >= 8 else {
            lastErrorMessage = "Password must be at least 8 characters."
            statusText = "Use a longer password, then try again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Creating your server account..."
        defer { isSavingAPIKey = false }
        backendAuthStore.saveLastEmail(email)

        do {
            let session = try await backendClient.signup(
                configuration: configuration,
                email: email,
                password: password,
                name: nil
            )
            storeBackendAuthSession(session)
            backendAuthPasswordText = ""
            statusText = defaultDisconnectedStatusText
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Couldn't create your server account."
            return false
        }
    }

    func loginBackendAccount() async -> Bool {
        guard let configuration = await ensureBackendConfigurationForAuth() else {
            lastErrorMessage = "Gemini Live server URL is missing."
            statusText = "Check the connection and try again."
            return false
        }
        guard let email = draftBackendAuthEmail else {
            lastErrorMessage = "Email is missing."
            statusText = "Enter your email, then try again."
            return false
        }
        guard let password = draftBackendAuthPassword else {
            lastErrorMessage = "Password is missing."
            statusText = "Enter your password, then try again."
            return false
        }
        guard password.count >= 8 else {
            lastErrorMessage = "Password must be at least 8 characters."
            statusText = "Use a longer password, then try again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Signing in to Gemini Live server..."
        defer { isSavingAPIKey = false }
        backendAuthStore.saveLastEmail(email)

        do {
            let session = try await backendClient.login(
                configuration: configuration,
                email: email,
                password: password
            )
            storeBackendAuthSession(session)
            backendAuthPasswordText = ""
            statusText = defaultDisconnectedStatusText
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Couldn't sign in to Gemini Live server."
            return false
        }
    }

    private struct PortableBackendAuthSession: Decodable {
        let accessToken: String
        let expiresAt: String
        let refreshToken: String?
        let refreshExpiresAt: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
            case refreshToken = "refresh_token"
            case refreshExpiresAt = "refresh_expires_at"
        }
    }

    /// Applies a browser-issued login token into the app's secure storage.
    func applyWebSessionToken(_ rawToken: String) async -> Bool {
        let token = Self.normalizedPastedAccessToken(rawToken)
        guard !token.isEmpty else {
            lastErrorMessage = "Session token is empty."
            return false
        }
        guard await ensureBackendConfigurationForAuth() != nil else {
            lastErrorMessage = "Gemini Live server URL is missing."
            return false
        }
        guard let configuration = configuredBackendConfiguration else {
            lastErrorMessage = "Gemini Live server URL is missing."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        defer { isSavingAPIKey = false }

        let portableSession = Self.decodedPortableBackendAuthSession(from: token)
        let accessToken = portableSession?.accessToken ?? token
        let withToken = GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: accessToken
        )

        do {
            let user = try await backendClient.me(configuration: withToken)
            let session = GeminiLiveBackendAuthSession(
                accessToken: accessToken,
                expiresAt: portableSession?.expiresAt ?? Self.iso8601ExpiryForPastedSession(),
                refreshToken: portableSession?.refreshToken,
                refreshExpiresAt: portableSession?.refreshExpiresAt,
                user: user
            )
            storeBackendAuthSession(session)
            await refreshBackendSubscriptionStatus()
            return true
        } catch {
            lastErrorMessage = "Invalid or expired session token."
            return false
        }
    }

    /// Strips accidental `Bearer ` prefix and surrounding quotes from pasted tokens.
    private static func normalizedPastedAccessToken(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let prefix = "Bearer "
        if t.lowercased().hasPrefix(prefix.lowercased()) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2) || (t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private static func decodedPortableBackendAuthSession(from token: String) -> PortableBackendAuthSession? {
        let prefix = "nts_"
        guard token.hasPrefix(prefix) else { return nil }

        let encoded = String(token.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: Self.base64URLToBase64(encoded)) else { return nil }
        return try? JSONDecoder().decode(PortableBackendAuthSession.self, from: data)
    }

    private static func base64URLToBase64(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = replaced.count % 4
        guard remainder != 0 else { return replaced }
        return replaced + String(repeating: "=", count: 4 - remainder)
    }

    private static func iso8601ExpiryForPastedSession() -> String {
        let date = Date().addingTimeInterval(30 * 24 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var s = formatter.string(from: date)
        if s.hasSuffix("+00:00") {
            s = String(s.dropLast(6)) + "Z"
        }
        return s
    }

    func logoutBackendAccount() async {
        let configuration = configuredBackendUserConfiguration
        let refreshToken = storedBackendAuthSession?.refreshToken
        let shouldDisconnectManagedSession = selectedConnectionMethod == .managedServer
            && (connectionState == .connected || connectionState == .connecting)

        isSavingAPIKey = true
        defer { isSavingAPIKey = false }
        lastErrorMessage = nil

        if shouldDisconnectManagedSession {
            disconnect()
        }

        clearBackendAuthSession()
        backendAuthPasswordText = ""
        statusText = configuredBackendConfiguration == nil
            ? "Gemini Live server saved. Sign in to continue."
            : "Signed out from Gemini Live server."

        guard let configuration else { return }
        Task.detached(priority: .utility) { [backendClient] in
            let retryDelays: [Duration] = [.zero, .seconds(2), .seconds(5)]

            for delay in retryDelays {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }

                do {
                    try await backendClient.logout(configuration: configuration, refreshToken: refreshToken)
                    return
                } catch {
                    continue
                }
            }
        }
    }

    func connect(clearingTranscripts: Bool = true) {
        guard hasConfiguredConnection else {
            connectionState = .failed
            lastErrorMessage = selectedConnectionMethod == .userAPIKey
                ? "Gemini API key is missing."
                : "Gemini Live server is missing."
            statusText = defaultDisconnectedStatusText
            logConnectBlocked(reason: "missing configuration")
            return
        }

        if selectedConnectionMethod == .managedServer && !isProUser {
            connectionState = .failed
            lastErrorMessage = "Notch Pro is required to use the hosted Gemini Live server."
            statusText = defaultDisconnectedStatusText
            logConnectBlocked(reason: "managed server requires Pro")
            return
        }

        if clearingTranscripts { clearTranscripts() }
        lastDisconnectWasUserInitiated = false
        connectionState = .connecting
        isMicrophoneLive = false
        lastErrorMessage = nil
        statusText = "Requesting microphone access..."
        logConnectAttempt(clearingTranscripts: clearingTranscripts)

        requestMicrophoneAccess { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                guard granted else {
                    self.connectionState = .failed
                    self.lastErrorMessage = "Microphone access is required for Gemini Live."
                    self.statusText = "Enable microphone access for Notch in System Settings."
                    NotchLog.gemini.error("Connect failed: microphone permission denied")
                    return
                }

                self.statusText = "Connecting to Gemini Live..."
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
                        guard let configuredBackend = await self.freshConfiguredBackendUserConfiguration() else {
                            self.connectionState = .failed
                            self.lastErrorMessage = self.configuredBackendConfiguration == nil
                                ? "Gemini Live server is missing."
                                : "Please sign in to your Gemini Live server account."
                            self.statusText = self.defaultDisconnectedStatusText
                            self.logConnectBlocked(reason: "managed server auth missing")
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
                            if self.shouldClearBackendAuthSession(for: error) {
                                self.logGeminiFailure(
                                    "session token request rejected the saved session; clearing local auth",
                                    error: error
                                )
                                self.clearBackendAuthSession()
                            } else {
                                self.logGeminiFailure("session token request failed", error: error)
                            }
                            self.connectionState = .failed
                            self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            self.statusText = "Couldn't create a Gemini Live session token."
                            return
                        }
                    case .userAPIKey:
                        guard let configuredAPIKey = self.configuredAPIKey else {
                            self.connectionState = .failed
                            self.lastErrorMessage = "Gemini API key is missing."
                            self.statusText = self.defaultDisconnectedStatusText
                            self.logConnectBlocked(reason: "API key missing")
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
                    microphoneEnabled: self.effectiveMicrophoneEnabled,
                    thinkingBudget: preset.thinkingEnum.budget,
                    voiceName: preset.voiceEnum.apiName,
                    enabledTools: skillSnapshot.effectiveTools,
                    skillSnapshot: skillSnapshot,
                    resumeSession: !clearingTranscripts
                )
            }
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
        stopScreenCapture()
        pendingExecApprovals.removeAll()
        toastClearTask?.cancel()
        toastClearTask = nil
        lastToolAction = nil
        isModelThinking = false
        isHoldToTalkActive = false
        isMicrophoneLive = false
        // Transcript có thể rất dài; giữ lại sau khi ngắt kết nối làm RAM không giảm trong Activity Monitor.
        clearTranscripts()
        currentSkillSnapshot = nil
        session.disconnect(userInitiated: true)
        connectionState = .disconnected
        statusText = defaultDisconnectedStatusText
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard reconnectAttempt < maxReconnectAttempts else {
            isAutoReconnecting = false
            statusText = "Connection lost. Please reconnect manually."
            return
        }
        let delay = pow(2.0, Double(reconnectAttempt)) * 3.0 // 3s, 6s, 12s
        reconnectAttempt += 1
        isAutoReconnecting = true
        statusText = "Reconnecting... (attempt \(reconnectAttempt)/\(maxReconnectAttempts))"

        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.lastDisconnectWasUserInitiated = false
            self.connect(clearingTranscripts: false)
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        isAutoReconnecting = false
    }

    func startFullScreenSharing() {
        guard ensureScreenCapturePermission() else { return }
        screenRegionSelectionController.cancelSelection(notify: false)
        windowShareSelectionController.cancelSelection(notify: false)
        screenShareMode = .fullScreen
        screenShareRegion = nil
        screenShareFilter = nil
        screenShareHighlightController.hide()
        beginScreenCapture(statusMessage: "Sharing full screen.")
    }

    func startRegionScreenSharing() {
        guard ensureScreenCapturePermission() else { return }
        let wasSharing = isScreenSharingEnabled
        let previousMode = screenShareMode
        let previousRegion = screenShareRegion
        let previousFilter = screenShareFilter

        pauseScreenCapture()
        isScreenSharingEnabled = false
        screenShareHighlightController.hide()
        statusText = "Drag to select a screen region. Press Esc to cancel."

        screenRegionSelectionController.beginSelection { [weak self] rect in
            guard let self else { return }

            guard let rect, rect.width >= 12, rect.height >= 12 else {
                if wasSharing {
                    self.screenShareMode = previousMode
                    self.screenShareRegion = previousRegion
                    self.screenShareFilter = previousFilter
                    self.beginScreenCapture(statusMessage: self.statusMessage(for: previousMode, selectedFilter: previousFilter))
                } else if self.connectionState == .connected || self.connectionState == .connecting {
                    self.statusText = "Region selection cancelled."
                }
                return
            }

            self.screenShareMode = .selectedRegion
            self.screenShareRegion = rect.integral
            self.screenShareFilter = nil
            self.updateScreenShareHighlight()
            self.beginScreenCapture(statusMessage: "Sharing selected region.")
        }
    }

    func startWindowSharing() {
        guard ensureScreenCapturePermission() else { return }
        let wasSharing = isScreenSharingEnabled
        let previousMode = screenShareMode
        let previousRegion = screenShareRegion
        let previousFilter = screenShareFilter

        pauseScreenCapture()
        isScreenSharingEnabled = false
        screenShareHighlightController.hide()
        statusText = "Choose an app or window to share."

        windowShareSelectionController.beginSelection { [weak self] selectedFilter in
            guard let self else { return }

            guard let selectedFilter else {
                if wasSharing {
                    self.screenShareMode = previousMode
                    self.screenShareRegion = previousRegion
                    self.screenShareFilter = previousFilter
                    self.beginScreenCapture(statusMessage: self.statusMessage(for: previousMode, selectedFilter: previousFilter))
                } else if self.connectionState == .connected || self.connectionState == .connecting {
                    self.statusText = "App or window selection cancelled."
                }
                return
            }

            self.screenShareMode = .appWindow
            self.screenShareRegion = nil
            self.screenShareFilter = selectedFilter
            self.updateScreenShareHighlight()
            self.beginScreenCapture(statusMessage: self.statusMessage(for: .appWindow, selectedFilter: selectedFilter))
        }
    }

    func stopScreenSharing() {
        stopScreenCapture()
        if connectionState == .connected || connectionState == .connecting {
            statusText = "Screen sharing stopped."
        }
    }

    private func beginScreenCapture(statusMessage: String) {
        pauseScreenCapture()
        isScreenSharingEnabled = true
        statusText = statusMessage

        let captureSession = session
        updateScreenShareHighlight()

        screenCaptureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                guard let self else { break }

                guard let jpeg = await self.captureAndEncodeScreen(
                    region: self.screenShareRegion, 
                    contentFilter: self.screenShareFilter
                ) else { continue }

                self.updateScreenShareHighlight()
                captureSession.sendScreenFrame(jpeg)
            }
        }
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        if granted {
            return true
        }

        lastErrorMessage = "Screen Recording permission is required to share your screen."
        statusText = "Allow Screen Recording for Notch, then try again."
        return false
    }

    private func pauseScreenCapture() {
        screenCaptureTask?.cancel()
        screenCaptureTask = nil
        isScreenSharingEnabled = false
    }

    private func stopScreenCapture() {
        screenRegionSelectionController.cancelSelection(notify: false)
        windowShareSelectionController.cancelSelection(notify: false)
        pauseScreenCapture()
        screenShareHighlightController.hide()
    }

    private func updateScreenShareHighlight() {
        guard isScreenSharingEnabled || screenShareMode != .fullScreen else {
            screenShareHighlightController.hide()
            return
        }

        switch screenShareMode {
        case .fullScreen:
            screenShareHighlightController.hide()
        case .selectedRegion:
            guard let screenShareRegion else {
                screenShareHighlightController.hide()
                return
            }
            screenShareHighlightController.show(rect: screenShareRegion)
        case .appWindow:
            screenShareHighlightController.hide()
        }
    }

    private func captureAndEncodeScreen(region: CGRect?, contentFilter: SCContentFilter?) async -> Data? {
        if #available(macOS 14.0, *), let contentFilter {
            return await captureAndEncodeSharedContent(contentFilter)
        }

        return await captureAndEncodeDisplayRegion(region)
    }

    private func captureAndEncodeDisplayRegion(_ region: CGRect?) async -> Data? {
        let captureRect = region ?? NSScreen.main.map { screen in
            CGRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
        } ?? CGRect.infinite

        return await Task.detached(priority: .userInitiated) {
            guard let fullImage = CGWindowListCreateImage(
                captureRect, .optionAll, kCGNullWindowID, [.boundsIgnoreFraming]
            ) else { return nil }
            return Self.encodeJPEG(from: fullImage)
        }.value
    }

    private nonisolated static let jpegContext = CIContext(options: [.useSoftwareRenderer: false])

    private nonisolated static func encodeJPEG(from fullImage: CGImage) -> Data? {
        let maxWidth: CGFloat = 1280
        let originalWidth = CGFloat(fullImage.width)
        let scale = min(1.0, maxWidth / originalWidth)
        
        let ciImage = CIImage(cgImage: fullImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return jpegContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6])
    }

    @available(macOS 14.0, *)
    private func captureAndEncodeSharedContent(_ contentFilter: SCContentFilter) async -> Data? {
        let contentInfo = SCShareableContent.info(for: contentFilter)
        let contentRect = contentInfo.contentRect.standardized
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }

        let streamConfiguration = SCStreamConfiguration()
        let pixelScale = CGFloat(max(contentInfo.pointPixelScale, 1))
        streamConfiguration.width = max(Int((contentRect.width * pixelScale).rounded(.up)), 1)
        streamConfiguration.height = max(Int((contentRect.height * pixelScale).rounded(.up)), 1)
        streamConfiguration.showsCursor = false

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: streamConfiguration) { image, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }

        guard let image else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.encodeJPEG(from: image)
        }.value
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
        if connectionState == .connected {
            statusText = connectedMicStatusText
        }
    }

    func setOpenMicrophoneEnabled(_ enabled: Bool) {
        guard isMicrophoneEnabled != enabled else { return }
        isMicrophoneEnabled = enabled
        guard inputMode == .openMic else { return }
        syncEffectiveMicrophoneState()
        if connectionState == .connected {
            statusText = connectedMicStatusText
        }
    }

    func beginHoldToTalk() {
        guard inputMode == .pushToTalk else { return }
        guard connectionState == .connected else { return }
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
        if connectionState == .connected {
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
        guard connectionState == .connected else { return false }
        session.sendClientTextTurn(trimmed)
        userTranscript = trimmed
        isModelThinking = true
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
        currentSkillSnapshot = nil
        pendingExecApprovals.removeAll()
        isModelThinking = false
        subscriptions.removeAll()
        screenRegionSelectionController.cancelSelection(notify: false)
        windowShareSelectionController.cancelSelection(notify: false)
        session.disconnect(userInitiated: true)
    }

    private func statusMessage(for mode: ScreenShareMode, selectedFilter: SCContentFilter?) -> String {
        switch mode {
        case .fullScreen:
            return "Sharing full screen."
        case .selectedRegion:
            return "Sharing selected region."
        case .appWindow:
            guard let selectedFilter else {
                return "Sharing selected app or window."
            }
            let style = SCShareableContent.info(for: selectedFilter).style
            switch style {
            case .application:
                return "Sharing selected app."
            case .window:
                return "Sharing selected window."
            default:
                return "Sharing selected content."
            }
        }
    }

    func approveCurrentExecApprovalOnce() {
        guard let request = currentPendingExecApproval else { return }
        pendingExecApprovals.removeAll { $0.toolCallID == request.toolCallID }
        session.approveExecCall(toolCallID: request.toolCallID)
    }

    func approveCurrentExecApprovalExact() {
        guard let request = currentPendingExecApproval else { return }
        execApprovalStore.approveExact(command: request.command, workingDirectory: request.workingDirectory)
        pendingExecApprovals.removeAll { $0.toolCallID == request.toolCallID }
        session.approveExecCall(toolCallID: request.toolCallID)
    }

    func approveCurrentExecApprovalFamily() {
        guard let request = currentPendingExecApproval else { return }
        execApprovalStore.approveFamily(command: request.command, workingDirectory: request.workingDirectory)
        pendingExecApprovals.removeAll { $0.toolCallID == request.toolCallID }
        session.approveExecCall(toolCallID: request.toolCallID)
    }

    func denyCurrentExecApproval() {
        guard let request = currentPendingExecApproval else { return }
        pendingExecApprovals.removeAll { $0.toolCallID == request.toolCallID }
        session.denyExecCall(toolCallID: request.toolCallID)
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
        guard !skillStore.isBuiltInSkill(named: name) else {
            lastErrorMessage = "Built-in skill \"\(name)\" can't be deleted."
            statusText = "Skill deletion blocked."
            return
        }

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
        let currentBackendAuthSession = backendAuthStore.read()
        storedBackendAuthSession = currentBackendAuthSession
        backendAuthenticatedEmail = currentBackendAuthSession?.user.email
        backendAuthEmailText = currentBackendAuthSession?.user.email ?? backendAuthStore.readLastEmail()
        syncConfiguredConnectionState(updateStatus: connectionState != .connected && connectionState != .connecting)
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
        guard connectionState == .connected || connectionState == .connecting else { return }
        session.setMicrophoneEnabled(effectiveMicrophoneEnabled)
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

    private var configuredBackendConfigurationForAuth: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: nil
        )
    }

    private var needsBackendConfigurationSave: Bool {
        guard let draftBackendURL else { return configuredBackendConfiguration == nil }
        guard let configuration = configuredBackendConfiguration else { return true }

        return configuration.displayURL != draftBackendURL
            || configuration.clientToken != draftBackendClientToken
    }

    private var configuredBackendConfigurationWithAuth: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: storedBackendAuthSession?.accessToken
        )
    }

    private var configuredBackendUserConfiguration: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration,
              let session = storedBackendAuthSession else {
            return nil
        }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: nil,
            userAccessToken: session.accessToken
        )
    }

    private func parsedISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func backendAccessTokenNeedsRefresh(_ session: GeminiLiveBackendAuthSession) -> Bool {
        guard let expiresAt = parsedISO8601Date(session.expiresAt) else { return true }
        return expiresAt <= Date().addingTimeInterval(5 * 60)
    }

    private func backendRefreshTokenExpired(_ session: GeminiLiveBackendAuthSession) -> Bool {
        guard let refreshExpiresAt = session.refreshExpiresAt else { return false }
        guard let expiresAt = parsedISO8601Date(refreshExpiresAt) else { return true }
        return expiresAt <= Date()
    }

    private func loadCurrentBackendAuthSession() -> GeminiLiveBackendAuthSession? {
        if let storedBackendAuthSession {
            return storedBackendAuthSession
        }

        let currentBackendAuthSession = backendAuthStore.read()
        if let currentBackendAuthSession {
            storedBackendAuthSession = currentBackendAuthSession
            backendAuthenticatedEmail = currentBackendAuthSession.user.email
            backendAuthEmailText = currentBackendAuthSession.user.email
        }
        return currentBackendAuthSession
    }

    private func refreshBackendAuthSessionIfNeeded(forceRefresh: Bool = false) async -> GeminiLiveBackendAuthSession? {
        guard let session = loadCurrentBackendAuthSession() else { return nil }

        if backendRefreshTokenExpired(session) {
            clearBackendAuthSession()
            return nil
        }

        if !forceRefresh && !backendAccessTokenNeedsRefresh(session) {
            return session
        }

        guard let refreshToken = session.refreshToken,
              !refreshToken.isEmpty,
              let configuration = configuredBackendConfigurationForAuth else {
            if let accessExpiry = parsedISO8601Date(session.expiresAt), accessExpiry > Date(), !forceRefresh {
                return session
            }
            clearBackendAuthSession()
            return nil
        }

        if let backendAuthRefreshTask {
            do {
                let refreshedSession = try await backendAuthRefreshTask.value
                storeBackendAuthSession(refreshedSession)
                return refreshedSession
            } catch {
                if shouldClearBackendAuthSession(for: error) {
                    clearBackendAuthSession()
                }
                return nil
            }
        }

        let task = Task { [backendClient] in
            try await backendClient.refresh(configuration: configuration, refreshToken: refreshToken)
        }
        backendAuthRefreshTask = task
        defer { backendAuthRefreshTask = nil }

        do {
            let refreshedSession = try await task.value
            storeBackendAuthSession(refreshedSession)
            return refreshedSession
        } catch {
            if shouldClearBackendAuthSession(for: error) {
                clearBackendAuthSession()
            } else if let accessExpiry = parsedISO8601Date(session.expiresAt), accessExpiry > Date(), !forceRefresh {
                return session
            }
            return nil
        }
    }

    private func freshConfiguredBackendUserConfiguration(forceRefresh: Bool = false) async -> GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration,
              let session = await refreshBackendAuthSessionIfNeeded(forceRefresh: forceRefresh) else {
            return nil
        }

        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: nil,
            userAccessToken: session.accessToken
        )
    }

    private var backendAuthorizationToken: String? {
        configuredBackendConfigurationWithAuth?.authorizationToken
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

        return configuredBackendConfigurationForAuth
    }

    private func storeBackendAuthSession(_ session: GeminiLiveBackendAuthSession) {
        _ = backendAuthStore.save(session)
        storedBackendAuthSession = session
        backendAuthenticatedEmail = session.user.email
        backendAuthEmailText = session.user.email
        backendAuthStore.saveLastEmail(session.user.email)
        lastErrorMessage = nil
        isProFromBackend = session.user.isPro ?? false
        recomputeProEntitlement()
        syncConfiguredConnectionState()
    }

    private func clearBackendAuthSession() {
        let preservedEmail = draftBackendAuthEmail
        backendAuthRefreshTask?.cancel()
        backendAuthRefreshTask = nil
        backendAuthStore.delete()
        if let preservedEmail {
            backendAuthStore.saveLastEmail(preservedEmail)
        }
        storedBackendAuthSession = nil
        backendAuthenticatedEmail = nil
        isProFromBackend = false
        recomputeProEntitlement()
        syncConfiguredConnectionState()
    }

    private func shouldClearBackendAuthSession(for error: Error) -> Bool {
        if let backendError = error as? GeminiLiveBackendError {
            switch backendError {
            case .unauthorized:
                return true
            case let .server(message):
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized.contains("invalid or expired session token")
                    || normalized.contains("session token")
                    || normalized.contains("unauthorized")
            default:
                return false
            }
        }

        let normalized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("invalid or expired session token")
            || normalized.contains("unauthorized")
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
