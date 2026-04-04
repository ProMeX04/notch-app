@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import Security
import SwiftUI

@MainActor
final class GeminiLiveViewModel: ObservableObject {
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

    // All three properties below are per-preset: reading reflects the active preset,
    // writing updates the active preset and persists.
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
    @Published var showTranscriptOverlay: Bool = true {
        didSet { persistSettings() }
    }
    @Published private(set) var systemPromptPresets: [GeminiSystemPromptPreset] = GeminiSystemPromptPreset.defaultPresets
    @Published private(set) var selectedSystemPromptID = GeminiSystemPromptPreset.defaultPreset.id
    @Published private(set) var hasSavedAPIKey = false
    @Published private(set) var isSavingAPIKey = false
    @Published private(set) var lastToolAction: ToolActionToast?
    @Published private(set) var displayedImageOverlay: ImageOverlayRequest?
    @Published private(set) var overlayInput = TranscriptOverlayInput.idle
    @Published private(set) var isAutoReconnecting = false
    private var toastClearTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private var lastDisconnectWasUserInitiated = false
    private var pendingTurnSeparator = false
    private var screenCaptureTimer: Timer?
    private let session: GeminiLiveSession
    private let keyStore: GeminiLiveAPIKeyStore
    private let settingsStore: GeminiLiveSettingsStore

    weak var pomodoro: PomodoroViewModel?
    weak var countdown: CountdownViewModel?
    weak var counter: CounterViewModel?
    weak var playback: MusicProbeViewModel?
    private let environmentAPIKey: String?
    private let environmentPexelsAPIKey: String?
    private let environmentBraveSearchAPIKey: String?
    private var storedAPIKey: String?

    @Published var pexelsAPIKeyText: String = "" {
        didSet {
            let trimmed = pexelsAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: "dev.notch.pexels-api-key")
        }
    }
    @Published var braveSearchAPIKeyText: String = "" {
        didSet {
            let trimmed = braveSearchAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: "dev.notch.brave-search-api-key")
        }
    }

    init(processInfo: ProcessInfo = .processInfo, session: GeminiLiveSession = GeminiLiveSession()) {
        self.session = session
        environmentAPIKey = processInfo.environment["GEMINI_API_KEY"]
        environmentPexelsAPIKey = processInfo.environment["PEXELS_API_KEY"]
        environmentBraveSearchAPIKey = processInfo.environment["BRAVE_SEARCH_API_KEY"]
        keyStore = GeminiLiveAPIKeyStore(processInfo: processInfo)
        settingsStore = GeminiLiveSettingsStore()

        if let savedSettings = settingsStore.read() {
            isMicrophoneEnabled = savedSettings.isMicrophoneEnabled
            showTranscriptOverlay = savedSettings.showTranscriptOverlay
            systemPromptPresets = savedSettings.systemPromptPresets
            selectedSystemPromptID = savedSettings.selectedSystemPromptID
        }

        if let environmentAPIKey, !environmentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiKeyText = environmentAPIKey
            hasSavedAPIKey = true
            statusText = "Using GEMINI_API_KEY from the current environment."
        } else if let storedKey = keyStore.read(), !storedKey.isEmpty {
            storedAPIKey = storedKey
            apiKeyText = storedKey
            hasSavedAPIKey = true
            statusText = "Ready to connect to Gemini Live."
        } else {
            apiKeyText = ""
        }

        // Load stored API keys for auxiliary services without triggering didSet saves.
        let defaults = UserDefaults.standard
        _pexelsAPIKeyText = Published(initialValue: defaults.string(forKey: "dev.notch.pexels-api-key") ?? "")
        _braveSearchAPIKeyText = Published(initialValue: defaults.string(forKey: "dev.notch.brave-search-api-key") ?? "")

        normalizeSystemPromptSelection()
        // Load all per-preset settings without triggering write-through didSets.
        let active = selectedSystemPromptPreset
        _thinkingLevel = Published(initialValue: active.thinkingEnum)
        _selectedVoice = Published(initialValue: active.voiceEnum)
        _enabledTools = Published(initialValue: active.toolSet)

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
                    // Reset counter on successful connect
                    self.reconnectAttempt = 0
                    self.isAutoReconnecting = false
                    self.reconnectTask = nil
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

        session.onTimerControl = { [weak self] timerName, action, duration, breakDuration, minutes, breakMinutes in
            final class Box: @unchecked Sendable { var value = "" }
            let box = Box()
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let self else { sema.signal(); return }
                box.value = self.executeControlTimerAction(
                    timer: timerName, action: action,
                    duration: duration, breakDuration: breakDuration,
                    minutes: minutes, breakMinutes: breakMinutes
                )
                sema.signal()
            }
            sema.wait()
            return box.value
        }

        session.onMediaControl = { [weak self] action, value, valueString in
            final class Box: @unchecked Sendable { var value = "" }
            let box = Box()
            let sema = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                guard let self else { sema.signal(); return }
                box.value = self.executeMediaAction(action: action, value: value, valueString: valueString)
                sema.signal()
            }
            sema.wait()
            return box.value
        }

        session.onFunctionExecuted = { [weak self] name, args, result in
            let action = args["action"] as? String
            let resultSuccess = result["success"] as? Bool
            let resultMessage = result["message"] as? String
            let resultError = result["error"] as? String
            DispatchQueue.main.async {
                guard let self else { return }
                if name == "controlApp" {
                    if let success = resultSuccess {
                        if success, let message = resultMessage {
                            self.postToolAction(label: message, icon: "macwindow")
                        } else if let error = resultError {
                            self.postToolAction(label: error, icon: "exclamationmark.triangle")
                        }
                    }
                } else if name == "controlBrowser" {
                    let actionWord = action == "open" ? "Opened link" : "Controlled tab"
                    self.postToolAction(label: actionWord, icon: "safari")
                } else if name == "readClipboard" {
                    self.postToolAction(label: "Read clipboard", icon: "doc.on.clipboard")
                } else if name == "manageNotes" {
                    let actionLabel = action == "add_reminder" ? "Added reminder" : "Added note"
                    self.postToolAction(label: actionLabel, icon: "square.and.pencil")
                } else if name == "displayImage" {
                    if let success = resultSuccess {
                        if !success, let error = resultError {
                            self.postToolAction(label: error, icon: "exclamationmark.triangle")
                        }
                    }
                }
            }
        }

        session.onDisplayImageRequest = { [weak self] request in
            DispatchQueue.main.async {
                self?.displayedImageOverlay = request
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
                toolAction: toolAction,
                imageRequest: image,
                subsEnabled: subsOn,
                isConnected: state == .connected || state == .connecting
            )
        }
        .assign(to: &$overlayInput)
    }

    var hasConfiguredAPIKey: Bool {
        !(configuredAPIKey?.isEmpty ?? true)
    }

    var selectedSystemPromptPreset: GeminiSystemPromptPreset {
        systemPromptPresets.first(where: { $0.id == selectedSystemPromptID })
            ?? systemPromptPresets.first
            ?? GeminiSystemPromptPreset.defaultPreset
    }

    var selectedSystemPromptTitle: String {
        selectedSystemPromptPreset.title
    }

    var canDeleteSelectedSystemPrompt: Bool {
        systemPromptPresets.count > 1
    }

    func selectSystemPrompt(id: String) {
        guard systemPromptPresets.contains(where: { $0.id == id }) else { return }
        guard selectedSystemPromptID != id else { return }
        selectedSystemPromptID = id
        let active = selectedSystemPromptPreset
        _thinkingLevel = Published(initialValue: active.thinkingEnum)
        _selectedVoice = Published(initialValue: active.voiceEnum)
        _enabledTools = Published(initialValue: active.toolSet)
        persistSettings()
    }

    func systemPromptPreset(id: String) -> GeminiSystemPromptPreset? {
        systemPromptPresets.first(where: { $0.id == id })
    }

    @discardableResult
    func saveSystemPrompt(id: String?, title: String, content: String) -> Bool {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Prompt \(systemPromptPresets.count + (id == nil ? 1 : 0))" : trimmedTitle

        if let id, let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) {
            systemPromptPresets[existingIndex].title = resolvedTitle
            systemPromptPresets[existingIndex].content = trimmedContent
            // Tools are managed separately; don't touch them here.
            selectedSystemPromptID = id
        } else {
            // New presets start with no tools, default voice, and no thinking.
            let preset = GeminiSystemPromptPreset(
                id: UUID().uuidString,
                title: resolvedTitle,
                content: trimmedContent,
                enabledTools: [],
                voice: GeminiVoice.kore.rawValue,
                thinkingLevel: GeminiThinkingLevel.off.rawValue
            )
            systemPromptPresets.append(preset)
            selectedSystemPromptID = preset.id
            _thinkingLevel = Published(initialValue: .off)
            _selectedVoice = Published(initialValue: .kore)
            _enabledTools = Published(initialValue: [])
        }

        normalizeSystemPromptSelection()
        persistSettings()
        return true
    }

    @discardableResult
    func deleteSystemPrompt(id: String) -> Bool {
        guard systemPromptPresets.count > 1 else { return false }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) else { return false }

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

    private func buildSystemPrompt(currentTime: String) -> String {
        let promptBody = selectedSystemPromptPreset.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPromptBody = promptBody.isEmpty ? GeminiSystemPromptPreset.defaultPreset.content : promptBody

        return """
        \(resolvedPromptBody)

        Current context:
        - Time: \(currentTime) (Hanoi timezone, UTC+7)
        - Location: Hanoi, Vietnam

        Tool rules:
        - When the user wants to open music, a song, an album, an artist, or a music video without giving a direct link, use the `controlBrowser` tool with `action: "open"` and pass the target text in `query`. The app will use DuckDuckGo Lucky to open the best matching result in the default browser.
        - When the user wants you to show a photo, wallpaper, illustration, or inspirational image on screen, use the `displayImage` tool with a short descriptive `query`.
        """
    }

    private func executeControlTimerAction(
        timer: String, action: String,
        duration: String?, breakDuration: String?,
        minutes: Int?, breakMinutes: Int?
    ) -> String {
        // Resolve seconds from duration string or fall back to minutes parameter
        func resolveSeconds(_ str: String?, fallbackMinutes: Int?, default defaultMinutes: Int) -> Int {
            if let str, let s = DurationParser.parse(str) { return s }
            return (fallbackMinutes ?? defaultMinutes) * 60
        }

        switch timer {
        case "pomodoro":
            guard let pom = pomodoro else { return "Pomodoro not available" }
            switch action {
            case "start":
                let focusSeconds = resolveSeconds(duration, fallbackMinutes: minutes, default: 30)
                let breakSeconds = resolveSeconds(breakDuration, fallbackMinutes: breakMinutes, default: 5)
                pom.updateCurrentDurations(
                    focusMinutes: focusSeconds / 60,
                    breakMinutes: max(1, breakSeconds / 60)
                )
                pom.start()
                let fl = DurationParser.displayString(for: focusSeconds)
                let bl = DurationParser.displayString(for: breakSeconds)
                postToolAction(label: "Pomodoro \(fl)/\(bl)", icon: "timer")
                return "Pomodoro started: \(fl) focus / \(bl) break"
            case "pause":
                pom.pause()
                postToolAction(label: "Pomodoro paused", icon: "pause.circle")
                return "Pomodoro paused, \(pom.remainingText()) remaining"
            case "resume":
                pom.start()
                postToolAction(label: "Pomodoro resumed", icon: "play.circle")
                return "Pomodoro resumed"
            case "reset":
                pom.reset()
                postToolAction(label: "Pomodoro reset", icon: "arrow.counterclockwise")
                return "Pomodoro reset"
            case "skip":
                pom.skipPhase()
                postToolAction(label: "Phase skipped", icon: "forward.end.fill")
                return "Skipped to next Pomodoro phase"
            default:
                return "Unknown action: \(action)"
            }
        case "countdown":
            guard let cd = countdown else { return "Countdown not available" }
            switch action {
            case "start":
                let secs = resolveSeconds(duration, fallbackMinutes: minutes, default: 10)
                cd.selectPreset(secs)
                cd.start()
                let label = DurationParser.displayString(for: cd.presetSeconds)
                postToolAction(label: "Countdown \(label)", icon: "timer")
                return "Countdown started for \(label)"
            case "pause":
                cd.pause()
                postToolAction(label: "Countdown paused", icon: "pause.circle")
                return "Countdown paused, \(cd.remainingText()) remaining"
            case "resume":
                cd.start()
                postToolAction(label: "Countdown resumed", icon: "play.circle")
                return "Countdown resumed"
            case "reset":
                cd.reset()
                postToolAction(label: "Countdown reset", icon: "arrow.counterclockwise")
                return "Countdown reset"
            default:
                return "Unknown action: \(action)"
            }
        case "stopwatch":
            guard let sw = counter else { return "Stopwatch not available" }
            switch action {
            case "start":
                sw.start()
                postToolAction(label: "Stopwatch started", icon: "stopwatch")
                return "Stopwatch started"
            case "pause":
                sw.pause()
                postToolAction(label: "Stopwatch paused", icon: "pause.circle")
                return "Stopwatch paused, \(sw.elapsedText(at: .now)) elapsed"
            case "resume":
                sw.start()
                postToolAction(label: "Stopwatch resumed", icon: "play.circle")
                return "Stopwatch resumed"
            case "reset":
                sw.reset()
                postToolAction(label: "Stopwatch reset", icon: "arrow.counterclockwise")
                return "Stopwatch reset"
            default:
                return "Unknown action: \(action)"
            }
        default:
            return "Unknown timer: \(timer)"
        }
    }

    private func executeMediaAction(action: String, value: Double?, valueString: String?) -> String {
        guard let pb = playback else { return "Media player not available" }

        // Resolve skip seconds: prefer free-form string (e.g. "30s", "1m"), fallback to numeric value
        func resolveSkipSeconds(default defaultVal: Double) -> Double {
            if let str = valueString, let secs = DurationParser.parse(str) { return Double(secs) }
            return value ?? defaultVal
        }

        let (result, icon): (String, String)
        switch action {
        case "play":
            if !pb.isPlaying { pb.togglePlay() }
            (result, icon) = ("Playing \(pb.primaryText)", "play.fill")
        case "pause":
            if pb.isPlaying { pb.togglePlay() }
            (result, icon) = ("Paused", "pause.fill")
        case "stop":
            pb.stop()
            (result, icon) = ("Stopped playback", "stop.fill")
        case "toggle":
            pb.togglePlay()
            (result, icon) = (pb.isPlaying ? "Paused" : "Playing", "playpause.fill")
        case "next":
            pb.nextTrack()
            (result, icon) = ("Next track", "forward.fill")
        case "previous":
            pb.previousTrack()
            (result, icon) = ("Previous track", "backward.fill")
        case "skip_forward":
            let secs = resolveSkipSeconds(default: 15)
            pb.skip(seconds: secs)
            (result, icon) = ("+\(Int(secs))s", "goforward")
        case "skip_backward":
            let secs = resolveSkipSeconds(default: 15)
            pb.skip(seconds: -secs)
            (result, icon) = ("-\(Int(secs))s", "gobackward")
        case "volume":
            guard let v = value else { return "Volume level required" }
            pb.setVolume(to: min(max(v / 100.0, 0), 1))
            (result, icon) = ("Volume \(Int(v))%", "speaker.wave.2.fill")
        case "shuffle":
            pb.toggleShuffle()
            (result, icon) = ("Shuffle", "shuffle")
        case "repeat":
            pb.toggleRepeat()
            (result, icon) = ("Repeat", "repeat")
        case "favorite":
            guard pb.supportsFavorite else {
                return "Favorite is only available when Apple Music is playing."
            }
            pb.toggleFavoriteTrack()
            (result, icon) = ("Favorite updated", "heart.fill")
        default:
            return "Unknown action: \(action)"
        }
        postToolAction(label: result, icon: icon)
        return result
    }

    func postToolAction(label: String, icon: String) {
        toastClearTask?.cancel()
        lastToolAction = ToolActionToast(label: label, icon: icon)
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
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

    var compactSymbolName: String {
        switch connectionState {
        case .connecting:
            return "waveform.and.mic"
        case .connected:
            return isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "waveform.and.mic"
        }
    }

    var compactAccentColor: NSColor {
        connectionState.accentColor
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

            guard environmentAPIKey == nil else {
                apiKeyText = draftAPIKey
                hasSavedAPIKey = true
                statusText = "GEMINI_API_KEY is being provided by the current environment."
                return true
            }

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

    func connect(clearingTranscripts: Bool = true) {
        guard let configuredAPIKey else {
            connectionState = .failed
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Save a Gemini API key, then connect again."
            return
        }

        if clearingTranscripts { clearTranscripts() }
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

                let systemPrompt = self.buildSystemPrompt(currentTime: currentTime)

                let preset = self.selectedSystemPromptPreset
                self.session.connect(
                    apiKey: configuredAPIKey,
                    model: "gemini-3.1-flash-live-preview",
                    systemPrompt: systemPrompt,
                    microphoneEnabled: self.isMicrophoneEnabled,
                    thinkingBudget: preset.thinkingEnum.budget,
                    voiceName: preset.voiceEnum.apiName,
                    pexelsAPIKey: self.configuredPexelsAPIKey,
                    braveSearchAPIKey: self.configuredBraveSearchAPIKey,
                    enabledTools: preset.toolSet,
                    resumeSession: !clearingTranscripts
                )
            }
        }
    }

    func disconnect() {
        lastDisconnectWasUserInitiated = true
        cancelReconnect()
        stopScreenCapture()
        displayedImageOverlay = nil
        toastClearTask?.cancel()
        toastClearTask = nil
        lastToolAction = nil
        // Transcript có thể rất dài; giữ lại sau khi ngắt kết nối làm RAM không giảm trong Activity Monitor.
        clearTranscripts()
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

    func toggleScreenSharing() {
        isScreenSharingEnabled.toggle()
        if isScreenSharingEnabled {
            startScreenCapture()
        } else {
            stopScreenCapture()
        }
    }

    private func startScreenCapture() {
        let captureSession = session
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task.detached {
                guard let jpeg = GeminiLiveViewModel.captureAndEncodeScreen() else { return }
                captureSession.sendScreenFrame(jpeg)
            }
        }
    }

    private func stopScreenCapture() {
        screenCaptureTimer?.invalidate()
        screenCaptureTimer = nil
        isScreenSharingEnabled = false
    }

    private nonisolated static func captureAndEncodeScreen() -> Data? {
        let mainScreenBounds = NSScreen.main.map { screen in
            CGRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
        } ?? CGRect.infinite

        guard let fullImage = CGWindowListCreateImage(
            mainScreenBounds, .optionAll, kCGNullWindowID, [.boundsIgnoreFraming]
        ) else { return nil }

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

    func toggleMicrophone() {
        isMicrophoneEnabled.toggle()
        session.setMicrophoneEnabled(isMicrophoneEnabled)
        statusText = isMicrophoneEnabled ? "Microphone is live." : "Microphone muted."
    }

    func clearTranscripts() {
        userTranscript = ""
        modelTranscript = ""
        pendingTurnSeparator = false
        isModelSpeaking = false
        lastErrorMessage = nil
    }

    func clearSavedKey() {
        guard environmentAPIKey == nil else {
            apiKeyText = environmentAPIKey ?? ""
            hasSavedAPIKey = true
            return
        }

        keyStore.delete()
        storedAPIKey = nil
        hasSavedAPIKey = false
        apiKeyText = ""
        if connectionState == .disconnected || connectionState == .failed {
            statusText = "Paste your Gemini API key to start Gemini Live."
        }
    }

    func shutdown() {
        session.disconnect(userInitiated: true)
    }

    func clearDisplayedImageOverlay() {
        displayedImageOverlay = nil
    }

    private func persistSettings() {
        settingsStore.save(
            GeminiLiveSettings(
                isMicrophoneEnabled: isMicrophoneEnabled,
                showTranscriptOverlay: showTranscriptOverlay,
                systemPromptPresets: systemPromptPresets,
                selectedSystemPromptID: selectedSystemPromptID
            )
        )
    }

    private var draftAPIKey: String? {
        let trimmedInput = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    private var configuredAPIKey: String? {
        if let environmentAPIKey {
            let trimmedEnvironmentKey = environmentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEnvironmentKey.isEmpty {
                return trimmedEnvironmentKey
            }
        }

        guard let storedKey = storedAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !storedKey.isEmpty else {
            return nil
        }
        return storedKey
    }

    private var configuredPexelsAPIKey: String? {
        if let environmentPexelsAPIKey {
            let trimmedEnvironmentKey = environmentPexelsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEnvironmentKey.isEmpty {
                return trimmedEnvironmentKey
            }
        }

        let defaults = UserDefaults.standard
        let storedKeys = [
            defaults.string(forKey: "PEXELS_API_KEY"),
            defaults.string(forKey: "dev.notch.pexels-api-key"),
        ]

        for candidate in storedKeys {
            guard let candidate else { continue }
            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCandidate.isEmpty {
                return trimmedCandidate
            }
        }

        return nil
    }

    private var configuredBraveSearchAPIKey: String? {
        if let environmentBraveSearchAPIKey {
            let trimmed = environmentBraveSearchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        let defaults = UserDefaults.standard
        let storedKeys = [
            defaults.string(forKey: "BRAVE_SEARCH_API_KEY"),
            defaults.string(forKey: "dev.notch.brave-search-api-key"),
        ]

        for candidate in storedKeys {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return nil
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
