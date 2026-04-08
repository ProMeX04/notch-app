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

    @Published private(set) var connectionState: GeminiLiveConnectionState = .disconnected
    @Published private(set) var isMicrophoneEnabled = true {
        didSet { persistSettings() }
    }
    @Published private(set) var statusText = "Paste your Gemini API key to start Gemini Live."
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var userTranscript = ""
    @Published private(set) var modelTranscript = ""
    @Published var apiKeyText: String

    @Published private(set) var isScreenSharingEnabled = false
    @Published private(set) var isModelSpeaking = false
    @Published private(set) var outputVolume = 1.0

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
    @Published private(set) var isSavingServiceKeys = false
    @Published private(set) var lastToolAction: ToolActionToast?
    @Published private(set) var displayedImageOverlay: ImageOverlayRequest?
    @Published private(set) var overlayInput = TranscriptOverlayInput.idle
    @Published private(set) var isAutoReconnecting = false
    @Published private(set) var pendingExecApprovals: [ExecApprovalRequest] = []
    private var toastClearTask: Task<Void, Never>?
    /// Clears `displayedImageOverlay` after a fixed delay so images never stick forever (e.g. when `isModelSpeaking` stays true).
    private var imageOverlayAutoDismissTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private var lastDisconnectWasUserInitiated = false
    private var pendingTurnSeparator = false
    private var screenCaptureTimer: Timer?
    private let screenRegionSelectionController = ScreenRegionSelectionController()
    private let windowShareSelectionController = WindowShareSelectionController()
    private let screenShareHighlightController = ScreenShareHighlightController()
    private var screenShareMode: ScreenShareMode = .fullScreen
    private var screenShareRegion: CGRect?
    private var screenShareFilter: SCContentFilter?
    private let session: GeminiLiveSession
    private let keyStore: GeminiLiveAPIKeyStore
    private let pexelsKeyStore: GeminiLiveSecretStore
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
    var onExecApprovalAttentionRequested: (() -> Void)?
    /// Present the service keys window (standard `NSWindow`, set by `NotchWindowController`).
    var onPresentSecretsPanel: (() -> Void)?

    @Published var pexelsAPIKeyText: String = ""

    var currentPendingExecApproval: ExecApprovalRequest? {
        pendingExecApprovals.first
    }

    init(processInfo: ProcessInfo = .processInfo, session: GeminiLiveSession = GeminiLiveSession()) {
        self.session = session
        keyStore = GeminiLiveAPIKeyStore(processInfo: processInfo)
        pexelsKeyStore = GeminiLiveSecretStore(
            processInfo: processInfo,
            developmentFileURL: GeminiLiveStoragePaths.developmentPexelsAPIKeyFile,
            keychainAccount: "PexelsAPIKey"
        )
        settingsStore = GeminiLiveSettingsStore()
        execApprovalStore = GeminiLiveExecApprovalStore()
        agentAvatarStore = GeminiAgentAvatarStore()
        skillStore = SkillStore()
        skillPackageService = SkillPackageService(skillStore: skillStore)
        userStore = UserStore()
        memoryStore = MemoryStore()
        installedSkills = skillStore.listInstalledSkills()

        if let savedSettings = settingsStore.read() {
            isMicrophoneEnabled = savedSettings.isMicrophoneEnabled
            showTranscriptOverlay = savedSettings.showTranscriptOverlay
            transcriptOverlayAutoHide = savedSettings.transcriptOverlayAutoHide
            showLiveChatInput = savedSettings.showLiveChatInput
            outputVolume = min(max(savedSettings.outputVolume, 0), 1)
            systemPromptPresets = savedSettings.systemPromptPresets
            selectedSystemPromptID = savedSettings.selectedSystemPromptID
        }

        if let storedKey = keyStore.read(), !storedKey.isEmpty {
            storedAPIKey = storedKey
            apiKeyText = storedKey
            hasSavedAPIKey = true
            statusText = "Ready to connect to Gemini Live."
        } else {
            apiKeyText = ""
        }

        _pexelsAPIKeyText = Published(initialValue: configuredPexelsAPIKey ?? "")

        normalizeSystemPromptSelection()
        // Load all per-preset settings without triggering write-through didSets.
        let active = selectedSystemPromptPreset
        _thinkingLevel = Published(initialValue: active.thinkingEnum)
        _selectedVoice = Published(initialValue: active.voiceEnum)
        _enabledTools = Published(initialValue: active.toolSet)
        _enabledSkillNames = Published(initialValue: Set(active.enabledSkillNames))
        normalizeEnabledSkillNames()
        syncEnabledSkillNamesToActivePreset()
        session.setOutputVolume(outputVolume)

        session.onStateChange = { [weak self] state, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.connectionState = state
                if let message, !message.isEmpty {
                    self.statusText = message
                } else {
                    self.statusText = self.hasConfiguredAPIKey ? "Ready to connect to Gemini Live." : "Paste your Gemini API key to start Gemini Live."
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

        session.onModelTranscript = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isModelSpeaking = true
                if self.modelTranscript.isEmpty {
                    self.modelTranscript = text
                } else if self.pendingTurnSeparator {
                    self.modelTranscript = text
                    self.pendingTurnSeparator = false
                } else {
                    self.modelTranscript += " " + text
                }
            }
        }

        session.onTurnComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isModelSpeaking = false
                if !self.modelTranscript.isEmpty {
                    self.pendingTurnSeparator = true
                }
            }
        }

        session.onFunctionStarted = { [weak self] name, _ in
            DispatchQueue.main.async {
                guard let self, let toast = self.startedToolAction(for: name) else { return }
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
            DispatchQueue.main.async {
                guard let self else { return }
                if let toast = self.completedToolAction(
                    for: name,
                    success: resultSuccess == true,
                    error: resultError
                ) {
                    self.postToolAction(
                        label: toast.label,
                        icon: toast.icon,
                        showsInOverlay: toast.showsInOverlay
                    )
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
                Publishers.CombineLatest($lastToolAction, $displayedImageOverlay),
                Publishers.CombineLatest($showTranscriptOverlay, $connectionState)
            )
        )
        .map { transcripts, rest in
            let (toolAction, image) = rest.0
            let (subsOn, state) = rest.1
            return TranscriptOverlayInput(
                userText: transcripts.0,
                modelText: transcripts.1,
                isModelSpeaking: transcripts.2,
                toolAction: toolAction.flatMap { $0.showsInOverlay ? $0 : nil },
                imageRequest: image,
                subsEnabled: subsOn,
                isConnected: state == .connected || state == .connecting
            )
        }
        .assign(to: &$overlayInput)

        persistSettings()
    }

    var hasConfiguredAPIKey: Bool {
        !(configuredAPIKey?.isEmpty ?? true)
    }

    func requestManageKeysPanel() {
        onPresentSecretsPanel?()
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
        _enabledTools = Published(initialValue: active.toolSet)
        _enabledSkillNames = Published(initialValue: Set(active.enabledSkillNames))
        normalizeEnabledSkillNames()
        syncEnabledSkillNamesToActivePreset()
        persistSettings()
    }

    func systemPromptPreset(id: String) -> GeminiSystemPromptPreset? {
        systemPromptPresets.first(where: { $0.id == id })
    }

    @discardableResult
    func createSystemPrompt() -> GeminiSystemPromptPreset {
        let preset = GeminiSystemPromptPreset(
            id: UUID().uuidString,
            title: nextDefaultAgentTitle(),
            content: "",
            enabledTools: [],
            voice: GeminiVoice.kore.rawValue,
            thinkingLevel: GeminiThinkingLevel.off.rawValue,
            lastUsedAt: Date()
        )
        systemPromptPresets.append(preset)
        selectedSystemPromptID = preset.id
        _thinkingLevel = Published(initialValue: .off)
        _selectedVoice = Published(initialValue: .kore)
        _enabledTools = Published(initialValue: [])
        _enabledSkillNames = Published(initialValue: [])
        persistSettings()
        return preset
    }

    func updateSelectedSystemPromptAvatar(symbolName: String) {
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        let resolvedSymbolName = GeminiSystemPromptPreset.availableAvatarSymbolNames.contains(symbolName)
            ? symbolName
            : GeminiSystemPromptPreset.defaultAvatarSymbolName
        guard systemPromptPresets[existingIndex].avatarSymbolName != resolvedSymbolName else { return }
        systemPromptPresets[existingIndex].avatarSymbolName = resolvedSymbolName
        persistSettings()
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
                thinkingLevel: GeminiThinkingLevel.off.rawValue,
                lastUsedAt: Date()
            )
            systemPromptPresets.append(preset)
            selectedSystemPromptID = preset.id
            _thinkingLevel = Published(initialValue: .off)
            _selectedVoice = Published(initialValue: .kore)
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
        currentTime: String,
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

        Current context:
        - Time: \(currentTime) (Hanoi timezone, UTC+7)
        - Location: Hanoi, Vietnam

        \(optionalToolRulesSection)
        \(optionalUserSection)
        \(optionalMemorySection)
        \(optionalSkillSection)
        """
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
            lines.append("- When the user asks for up-to-date information, use `webSearch` instead of guessing. This is the default web lookup tool.")
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

    private func completedToolAction(for name: String, success: Bool, error: String?) -> ToolActionToast? {
        if let error, !success {
            return ToolActionToast(label: error, icon: "exclamationmark.triangle", showsInOverlay: false)
        }

        guard success else { return nil }

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
            return "waveform.and.mic"
        }
    }

    var microphoneButtonTitle: String {
        isMicrophoneEnabled ? "Mute Mic" : "Unmute Mic"
    }

    var microphoneButtonIcon: String {
        isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
    }

    var canToggleMicrophone: Bool {
        connectionState == .connected || connectionState == .connecting
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
        connectionState == .connected && isMicrophoneEnabled
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

    func saveAPIKey() async -> Bool {
        guard let draftAPIKey else {
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Paste a Gemini API key, then save again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Testing Gemini API key..."
        defer { isSavingAPIKey = false }

        do {
            try await validateAPIKey(draftAPIKey)

            guard keyStore.save(draftAPIKey) else {
                lastErrorMessage = "Couldn't save the Gemini API key."
                statusText = keyStore.saveFailureMessage
                return false
            }

            storedAPIKey = draftAPIKey
            apiKeyText = draftAPIKey
            hasSavedAPIKey = true
            statusText = keyStore.saveSuccessMessage
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Gemini API key test failed."
            return false
        }
    }

    func saveServiceKeys() async -> Bool {
        let trimmedGeminiKey = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsGeminiSave = !trimmedGeminiKey.isEmpty && trimmedGeminiKey != (configuredAPIKey ?? "")

        if needsGeminiSave {
            guard await saveAPIKey() else { return false }
        } else if configuredAPIKey == nil {
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Paste a Gemini API key, then save again."
            return false
        }

        isSavingServiceKeys = true
        defer { isSavingServiceKeys = false }

        let didSavePexels = persistServiceKey(draftValue: pexelsAPIKeyText, store: pexelsKeyStore)

        guard didSavePexels else {
            lastErrorMessage = "Couldn't save one or more service keys."
            statusText = "Saving service keys failed."
            return false
        }

        pexelsAPIKeyText = configuredPexelsAPIKey ?? ""
        lastErrorMessage = nil
        statusText = "Keys saved."
        return true
    }

    func connect(clearingTranscripts: Bool = true) {
        guard let configuredAPIKey else {
            connectionState = .failed
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Save a Gemini API key, then connect again."
            return
        }

        if clearingTranscripts { clearTranscripts() }
        lastDisconnectWasUserInitiated = false
        connectionState = .connecting
        lastErrorMessage = nil
        statusText = "Requesting microphone access..."

        requestMicrophoneAccess { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                guard granted else {
                    self.connectionState = .failed
                    self.lastErrorMessage = "Microphone access is required for Gemini Live."
                    self.statusText = "Enable microphone access for Notch in System Settings."
                    return
                }

                self.statusText = "Connecting to Gemini Live..."
                let now = Date()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "vi_VN")
                formatter.dateFormat = "EEEE, dd/MM/yyyy HH:mm"
                formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
                let currentTime = formatter.string(from: now)

                let skillSnapshot: SkillSessionSnapshot
                if clearingTranscripts || self.currentSkillSnapshot == nil {
                    skillSnapshot = self.makeSkillSessionSnapshot()
                    self.currentSkillSnapshot = skillSnapshot
                } else {
                    skillSnapshot = self.currentSkillSnapshot ?? self.makeSkillSessionSnapshot()
                }

                let systemPrompt = self.buildSystemPrompt(
                    currentTime: currentTime,
                    activeSkills: skillSnapshot.activeSkills,
                    effectiveTools: skillSnapshot.effectiveTools,
                    userContent: userStore.readUserProfile(),
                    memoryContent: memoryStore.readMainMemory()
                )

                let preset = self.selectedSystemPromptPreset
                self.session.connect(
                    apiKey: configuredAPIKey,
                    model: "gemini-3.1-flash-live-preview",
                    systemPrompt: systemPrompt,
                    microphoneEnabled: self.isMicrophoneEnabled,
                    thinkingBudget: preset.thinkingEnum.budget,
                    voiceName: preset.voiceEnum.apiName,
                    enabledTools: skillSnapshot.effectiveTools,
                    skillSnapshot: skillSnapshot,
                    resumeSession: !clearingTranscripts
                )
            }
        }
    }

    func disconnect() {
        lastDisconnectWasUserInitiated = true
        cancelReconnect()
        stopScreenCapture()
        imageOverlayAutoDismissTask?.cancel()
        imageOverlayAutoDismissTask = nil
        displayedImageOverlay = nil
        pendingExecApprovals.removeAll()
        toastClearTask?.cancel()
        toastClearTask = nil
        lastToolAction = nil
        // Transcript có thể rất dài; giữ lại sau khi ngắt kết nối làm RAM không giảm trong Activity Monitor.
        clearTranscripts()
        currentSkillSnapshot = nil
        session.disconnect(userInitiated: true)
        connectionState = .disconnected
        statusText = hasConfiguredAPIKey ? "Ready to connect to Gemini Live." : "Paste your Gemini API key to start Gemini Live."
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
        let captureRegion = screenShareRegion
        let captureFilter = screenShareFilter
        updateScreenShareHighlight()
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                self.updateScreenShareHighlight()
                guard let jpeg = await GeminiLiveViewModel.captureAndEncodeScreen(region: captureRegion, contentFilter: captureFilter) else { return }
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
        screenCaptureTimer?.invalidate()
        screenCaptureTimer = nil
    }

    private func stopScreenCapture() {
        screenRegionSelectionController.cancelSelection(notify: false)
        windowShareSelectionController.cancelSelection(notify: false)
        pauseScreenCapture()
        isScreenSharingEnabled = false
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

    private nonisolated static func captureAndEncodeScreen(region: CGRect?, contentFilter: SCContentFilter?) async -> Data? {
        if let contentFilter {
            return await captureAndEncodeSharedContent(contentFilter)
        }

        return captureAndEncodeDisplayRegion(region)
    }

    private nonisolated static func captureAndEncodeDisplayRegion(_ region: CGRect?) -> Data? {
        let captureRect = region ?? NSScreen.main.map { screen in
            CGRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
        } ?? CGRect.infinite

        let fullImage = CGWindowListCreateImage(
            captureRect, .optionAll, kCGNullWindowID, [.boundsIgnoreFraming]
        )
        guard let fullImage else { return nil }
        return encodeJPEG(from: fullImage)
    }

    private nonisolated static func encodeJPEG(from fullImage: CGImage) -> Data? {
        let maxWidth: CGFloat = 1280
        let originalWidth = CGFloat(fullImage.width)
        let originalHeight = CGFloat(fullImage.height)
        let scale = min(1.0, maxWidth / originalWidth)
        let targetWidth = Int(originalWidth * scale)
        let targetHeight = Int(originalHeight * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(fullImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaled = context.makeImage() else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: scaled)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }

    @available(macOS 14.0, *)
    private nonisolated static func captureAndEncodeSharedContent(_ contentFilter: SCContentFilter) async -> Data? {
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
        return encodeJPEG(from: image)
    }

    func toggleMicrophone() {
        isMicrophoneEnabled.toggle()
        session.setMicrophoneEnabled(isMicrophoneEnabled)
        statusText = isMicrophoneEnabled ? "Microphone is live." : "Microphone muted."
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        guard isMicrophoneEnabled != enabled else { return }
        isMicrophoneEnabled = enabled
        session.setMicrophoneEnabled(isMicrophoneEnabled)
        statusText = isMicrophoneEnabled ? "Microphone is live." : "Microphone muted."
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

    /// Sends typed text over the Live socket as `realtimeInput.text` (required for Gemini 3.1 Flash Live during conversation).
    @discardableResult
    func sendLiveChatMessage(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard connectionState == .connected else { return false }
        session.sendClientTextTurn(trimmed)
        userTranscript = trimmed
        return true
    }

    func clearTranscripts() {
        userTranscript = ""
        modelTranscript = ""
        pendingTurnSeparator = false
        isModelSpeaking = false
        lastErrorMessage = nil
    }

    func clearSavedKey() {
        keyStore.delete()
        storedAPIKey = nil
        hasSavedAPIKey = false
        apiKeyText = ""
        if connectionState == .disconnected || connectionState == .failed {
            statusText = "Paste your Gemini API key to start Gemini Live."
        }
    }

    func shutdown() {
        currentSkillSnapshot = nil
        pendingExecApprovals.removeAll()
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

    func clearDisplayedImageOverlay() {
        imageOverlayAutoDismissTask?.cancel()
        imageOverlayAutoDismissTask = nil
        displayedImageOverlay = nil
    }

    private func scheduleImageOverlayAutoDismissIfNeeded() {
        imageOverlayAutoDismissTask?.cancel()
        guard let overlay = displayedImageOverlay else { return }
        let captureID = overlay.id
        imageOverlayAutoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.displayedImageOverlay?.id == captureID else { return }
            self.imageOverlayAutoDismissTask = nil
            self.displayedImageOverlay = nil
        }
    }

    func showDisplayedImageOverlay(query: String, caption: String?, orientation: String?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            postToolAction(label: "Image query is empty", icon: "exclamationmark.triangle")
            return
        }

        guard let apiKey = configuredPexelsAPIKey else {
            postToolAction(label: "[Pexels] API key is missing.", icon: "exclamationmark.triangle")
            onPresentSecretsPanel?()
            return
        }

        guard var components = URLComponents(string: "https://api.pexels.com/v1/search") else {
            postToolAction(label: "[Pexels] Couldn't create request.", icon: "exclamationmark.triangle")
            return
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "orientation", value: normalizedPexelsOrientationValue(orientation)),
        ]

        guard let url = components.url else {
            postToolAction(label: "[Pexels] Couldn't encode query.", icon: "exclamationmark.triangle")
            return
        }

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { [weak self] in
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        self?.postToolAction(label: "[Pexels] Invalid response.", icon: "exclamationmark.triangle")
                    }
                    return
                }

                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    let message = Self.decodePexelsOverlayError(from: data) ?? "Returned HTTP \(httpResponse.statusCode)."
                    await MainActor.run {
                        self?.postToolAction(label: "[Pexels] \(message)", icon: "exclamationmark.triangle")
                    }
                    return
                }

                let payload = try JSONDecoder().decode(OverlayPexelsSearchResponse.self, from: data)
                guard let photo = payload.photos.first,
                      let imageURL = photo.src.large2x ?? photo.src.large ?? photo.src.medium else {
                    await MainActor.run {
                        self?.postToolAction(label: "[Pexels] No matching images.", icon: "exclamationmark.triangle")
                    }
                    return
                }

                let resolvedCaption = (trimmedCaption?.isEmpty == false ? trimmedCaption : nil)
                    ?? trimmedQuery.prefix(1).uppercased() + trimmedQuery.dropFirst()

                let overlay = ImageOverlayRequest(
                    query: trimmedQuery,
                    imageURL: imageURL,
                    sourceURL: photo.url,
                    caption: resolvedCaption,
                    photographer: photo.photographer
                )

                await MainActor.run {
                    self?.displayedImageOverlay = overlay
                    self?.scheduleImageOverlayAutoDismissIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self?.postToolAction(
                        label: "[Pexels] Request failed: \(error.localizedDescription)",
                        icon: "exclamationmark.triangle"
                    )
                }
            }
        }
    }

    func showDisplayedImageOverlay(url: URL, query: String?, caption: String?) {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedQuery = (trimmedQuery?.isEmpty == false ? trimmedQuery : nil) ?? "image"
        let resolvedCaption = (trimmedCaption?.isEmpty == false ? trimmedCaption : nil) ?? "Image"

        displayedImageOverlay = ImageOverlayRequest(
            query: resolvedQuery,
            imageURL: url,
            sourceURL: url.isFileURL ? nil : url,
            caption: resolvedCaption,
            photographer: nil
        )
        scheduleImageOverlayAutoDismissIfNeeded()
    }

    private static func decodePexelsOverlayError(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(OverlayPexelsErrorResponse.self, from: data),
           !envelope.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envelope.error
        }

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        return nil
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

    func canDeleteSkill(_ skill: InstalledSkill) -> Bool {
        !skillStore.isBuiltInSkill(named: skill.metadata.name)
    }

    func clearKeyDrafts() {
        apiKeyText = ""
        pexelsAPIKeyText = ""
    }

    func reloadKeyDrafts() {
        let currentGeminiKey = currentStoredGeminiKey()
        storedAPIKey = currentGeminiKey
        apiKeyText = currentGeminiKey ?? ""
        pexelsAPIKeyText = currentStoredPexelsKey() ?? ""
    }

    private func persistSettings() {
        settingsStore.save(
            GeminiLiveSettings(
                isMicrophoneEnabled: isMicrophoneEnabled,
                showTranscriptOverlay: showTranscriptOverlay,
                transcriptOverlayAutoHide: transcriptOverlayAutoHide,
                showLiveChatInput: showLiveChatInput,
                outputVolume: outputVolume,
                systemPromptPresets: systemPromptPresets,
                selectedSystemPromptID: selectedSystemPromptID
            )
        )
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

    private var draftAPIKey: String? {
        let trimmedInput = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var configuredAPIKey: String? {
        currentStoredGeminiKey()
    }

    private var configuredPexelsAPIKey: String? {
        currentStoredPexelsKey()
    }

    private func currentStoredGeminiKey() -> String? {
        normalizedStoredSecret(storedAPIKey ?? keyStore.read())
    }

    private func currentStoredPexelsKey() -> String? {
        normalizedStoredSecret(pexelsKeyStore.read())
    }

    private func normalizedStoredSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func persistServiceKey(draftValue: String, store: GeminiLiveSecretStore) -> Bool {
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        return store.save(trimmed)
    }

    var hasConfiguredPexelsKey: Bool {
        configuredPexelsAPIKey != nil
    }

    private func normalizedPexelsOrientationValue(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "portrait":
            return "portrait"
        case "square":
            return "square"
        default:
            return "landscape"
        }
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

private struct OverlayPexelsSearchResponse: Decodable {
    let photos: [OverlayPexelsPhoto]
}

private struct OverlayPexelsPhoto: Decodable {
    let url: URL?
    let photographer: String?
    let src: OverlayPexelsPhotoSource
}

private struct OverlayPexelsPhotoSource: Decodable {
    let medium: URL?
    let large: URL?
    let large2x: URL?
}

private struct OverlayPexelsErrorResponse: Decodable {
    let error: String
}
