@preconcurrency import AVFoundation
import Foundation

// Internal to this module - used by GeminiLiveSession and its extensions
enum GeminiLiveCaptureMode {
    case webRTC
    case voiceProcessing
    case standard
}

struct PendingExecApprovalCall {
    let toolCallID: String
    let args: [String: Any]
    let command: String
    let workingDirectory: String?
    let timeoutSeconds: Double
}

final class GeminiLiveSession: @unchecked Sendable {
    var onStateChange: (@Sendable (GeminiLiveConnectionState, String?) -> Void)?
    var onUserTranscript: (@Sendable (String) -> Void)?
    var onModelTranscript: (@Sendable (String) -> Void)?
    var onTurnComplete: (@Sendable () -> Void)?
    var onFunctionExecuted: (@Sendable (_ name: String, _ args: [String: Any], _ result: [String: Any]) -> Void)?
    var onShouldAutoApproveExec: (@Sendable (_ command: String, _ workingDirectory: String?) -> Bool)?
    var onExecApprovalRequested: (@Sendable (ExecApprovalRequest) -> Void)?

    func sendScreenFrame(_ data: Data) {
        sendJSONObject([
            "realtimeInput": [
                "video": [
                    "data": data.base64EncodedString(),
                    "mimeType": "image/jpeg",
                ],
            ],
        ])
    }

    /// Sends typed user text during a live session.
    ///
    /// For `gemini-3.1-flash-live-preview`, Google documents that `clientContent` is only for
    /// seeding history with `historyConfig.initialHistoryInClientContent`; ongoing text must use
    /// `realtimeInput.text` (same as `send_realtime_input` in the official SDKs).
    func sendClientTextTurn(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendJSONObject([
            "realtimeInput": [
                "text": trimmed,
            ],
        ])
    }

    let urlSession = URLSession(configuration: .default)
    /// Shared ephemeral session for Brave search and other tool HTTP (not Pexels-specific).
    let toolHTTPURLSession = URLSession(configuration: .ephemeral)
    let sendQueue = DispatchQueue(label: "dev.notch.gemini.send")
    let audioProcessingQueue = DispatchQueue(label: "dev.notch.gemini.capture")
    let playbackQueue = DispatchQueue(label: "dev.notch.gemini.playback")

    func prefixedProviderMessage(_ provider: String, _ message: String) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return "[\(provider)] Unknown error." }
        guard !trimmedMessage.hasPrefix("[\(provider)]") else { return trimmedMessage }
        return "[\(provider)] \(trimmedMessage)"
    }

    let outputEngine = AVAudioEngine()
    let outputPlayer = AVAudioPlayerNode()
    let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    var standardInputEngine: AVAudioEngine?
    var inputConverter: AVAudioConverter?
    var microphoneTapInstalled = false
    var captureMode: GeminiLiveCaptureMode = .standard
    var webRTCAudioIO: GeminiLiveWebRTCAudioIO?
    var audioChunkCount = 0
    var audioCaptureMonitorWorkItem: DispatchWorkItem?
    let inputTargetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    var socketTask: URLSessionWebSocketTask?
    var enabledTools: Set<GeminiTool> = GeminiTool.coreToolSet
    var microphoneEnabled = true
    var outputVolume: Float = 1
    var outputPrepared = false
    var userInitiatedDisconnect = false
    var hasCompletedSetup = false
    var setupCompleteTime: Date?
    var modelHasSpoken = false
    var isFirstModelTurn = true
    var isResumingConnection = false
    var currentConfiguration: LiveSessionConfiguration?
    var latestSessionHandle: String?
    var latestSessionHandleIsResumable = false
    var pendingReconnectWorkItem: DispatchWorkItem?
    private let execApprovalQueue = DispatchQueue(label: "dev.notch.gemini.exec-approval")
    private var pendingExecApprovalsByID: [String: PendingExecApprovalCall] = [:]

    deinit {
        disconnect(userInitiated: true)
    }

    func connect(
        apiKey: String,
        model: String,
        systemPrompt: String?,
        microphoneEnabled: Bool,
        thinkingBudget: Int,
        voiceName: String = "Kore",
        braveSearchAPIKey: String? = nil,
        enabledTools: Set<GeminiTool> = GeminiTool.coreToolSet,
        skillSnapshot: SkillSessionSnapshot? = nil,
        resumeSession: Bool = false
    ) {
        cancelPendingReconnect()

        self.enabledTools = enabledTools
        self.microphoneEnabled = microphoneEnabled

        if !resumeSession {
            latestSessionHandle = nil
            latestSessionHandleIsResumable = false
        }

        let configuration = LiveSessionConfiguration(
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            thinkingBudget: thinkingBudget,
            voiceName: voiceName,
            braveSearchAPIKey: braveSearchAPIKey,
            skillSnapshot: skillSnapshot
        )
        currentConfiguration = configuration
        let shouldPreserveAudioSession = outputPrepared && captureMode == .webRTC

        startConnection(
            using: configuration,
            statusText: resumeSession && latestSessionHandle != nil ? "Resuming Gemini Live..." : "Connecting to Gemini Live...",
            displayState: resumeSession && latestSessionHandle != nil ? .connected : .connecting,
            preserveAudioSession: shouldPreserveAudioSession
        )
    }

    func disconnect(userInitiated: Bool) {
        userInitiatedDisconnect = userInitiated
        cancelPendingReconnect()

        if userInitiated {
            currentConfiguration = nil
            latestSessionHandle = nil
            latestSessionHandleIsResumable = false
            clearPendingExecApprovals()
        }

        tearDownConnection()

        if userInitiated {
            isResumingConnection = false
            onStateChange?(.disconnected, "Disconnected.")
        }
    }

    func enqueuePendingExecApproval(_ call: PendingExecApprovalCall) {
        execApprovalQueue.sync {
            pendingExecApprovalsByID[call.toolCallID] = call
        }
    }

    func takePendingExecApproval(toolCallID: String) -> PendingExecApprovalCall? {
        execApprovalQueue.sync {
            pendingExecApprovalsByID.removeValue(forKey: toolCallID)
        }
    }

    func clearPendingExecApprovals() {
        execApprovalQueue.sync {
            pendingExecApprovalsByID.removeAll()
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneEnabled = enabled

        guard socketTask != nil else { return }

        if captureMode == .webRTC, let webRTCAudioIO {
            webRTCAudioIO.setMicrophoneMuted(!enabled)

            if enabled {
                startMicrophone()
            } else {
                cancelAudioCaptureMonitor()
                sendJSONObject([
                    "realtimeInput": [
                        "audioStreamEnd": true,
                    ],
                ])
            }
            return
        }

        if enabled {
            startMicrophone()
        } else {
            stopMicrophone(notifyModel: true)
            cancelAudioCaptureMonitor()
        }
    }

    func setOutputVolume(_ volume: Double) {
        let clamped = Float(min(max(volume, 0), 1))
        outputVolume = clamped
        if captureMode == .webRTC {
            webRTCAudioIO?.setOutputVolume(clamped)
        } else {
            playbackQueue.async { [weak self] in
                self?.outputPlayer.volume = clamped
            }
        }
    }

    func liveURL(apiKey: String) -> URL? {
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
        ]
        return components?.url
    }

    var enabledToolDeclarations: [[String: Any]] {
        var decls: [[String: Any]] = []
        if enabledTools.contains(.webSearch) {
            decls.append([
                "name": "webSearch",
                "description": "Search the web and return a concise summary of the top results. Prefer Brave Search when a Brave API key is configured, and fall back to lightweight public search otherwise. Use this when the user asks for up-to-date information or facts you may not know.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "query": [
                            "type": "STRING",
                            "description": "The search query to look up."
                        ],
                        "maxResults": [
                            "type": "NUMBER",
                            "description": "Optional. Maximum number of results to return (1–10). Defaults to 5."
                        ]
                    ],
                    "required": ["query"]
                ]
            ])
        }
        if enabledTools.contains(.exec) {
            decls.append([
                "name": "exec",
                "description": "Run a local shell command on the user's Mac using zsh. Use this for command-line tools such as curl, jq, python3, or git. Commands run in ~/.notch/workspace by default unless a working directory is provided. New or untrusted commands may require approval. Prefer concise commands and read-only inspection unless the user clearly wants a change.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "command": [
                            "type": "STRING",
                            "description": "The exact shell command to run, for example: curl -s https://example.com"
                        ],
                        "workingDirectory": [
                            "type": "STRING",
                            "description": "Optional absolute path or ~/ path to run the command in. If omitted, Notch uses ~/.notch/workspace."
                        ],
                        "timeoutSeconds": [
                            "type": "NUMBER",
                            "description": "Optional timeout in seconds. Use 1-30. Defaults to 15."
                        ]
                    ],
                    "required": ["command"]
                ]
            ])
        }
        if enabledTools.contains(.read) {
            decls.append([
                "name": "read",
                "description": "Read a UTF-8 text file. Relative paths are resolved from ~/.notch/workspace. Absolute paths are allowed for files inside ~/.notch/workspace and for built-in skill SKILL.md locations listed in <available_skills>.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "path": [
                            "type": "STRING",
                            "description": "Relative path from ~/.notch/workspace, or an absolute path inside ~/.notch/workspace, or a built-in skill location from <available_skills>."
                        ]
                    ],
                    "required": ["path"]
                ]
            ])
        }
        if enabledTools.contains(.write) {
            decls.append([
                "name": "write",
                "description": "Create or overwrite a UTF-8 text file inside ~/.notch/workspace.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "path": [
                            "type": "STRING",
                            "description": "Relative path from ~/.notch/workspace, or an absolute path still inside that workspace."
                        ],
                        "content": [
                            "type": "STRING",
                            "description": "The full file contents to write."
                        ]
                    ],
                    "required": ["path", "content"]
                ]
            ])
        }
        if enabledTools.contains(.find) {
            decls.append([
                "name": "find",
                "description": "Find files or folders inside ~/.notch/workspace by name or relative path fragment.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "pattern": [
                            "type": "STRING",
                            "description": "Case-insensitive file or path fragment to look for."
                        ],
                        "baseDirectory": [
                            "type": "STRING",
                            "description": "Optional relative path inside ~/.notch/workspace to start from. Defaults to the workspace root."
                        ],
                        "maxResults": [
                            "type": "NUMBER",
                            "description": "Optional max number of matches to return. Use 1-100. Defaults to 20."
                        ]
                    ],
                    "required": ["pattern"]
                ]
            ])
        }
        if enabledTools.contains(.grep) {
            decls.append([
                "name": "grep",
                "description": "Search text content inside files in ~/.notch/workspace. Supports plain text and regular expressions.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "pattern": [
                            "type": "STRING",
                            "description": "Plain text or regular expression to search for."
                        ],
                        "path": [
                            "type": "STRING",
                            "description": "Optional file or directory path inside ~/.notch/workspace to search. Defaults to the workspace root."
                        ],
                        "maxResults": [
                            "type": "NUMBER",
                            "description": "Optional max number of matches to return. Use 1-100. Defaults to 20."
                        ]
                    ],
                    "required": ["pattern"]
                ]
            ])
        }
        if enabledTools.contains(.edit) {
            decls.append([
                "name": "edit",
                "description": "Make a precise string replacement in an existing UTF-8 text file inside ~/.notch/workspace.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "path": [
                            "type": "STRING",
                            "description": "Relative path from ~/.notch/workspace, or an absolute path still inside that workspace."
                        ],
                        "oldText": [
                            "type": "STRING",
                            "description": "The exact text to replace."
                        ],
                        "newText": [
                            "type": "STRING",
                            "description": "Replacement text."
                        ],
                        "replaceAll": [
                            "type": "BOOLEAN",
                            "description": "Replace every occurrence. Defaults to false."
                        ]
                    ],
                    "required": ["path", "oldText", "newText"]
                ]
            ])
        }

        return decls
    }

    func startConnection(
        using configuration: LiveSessionConfiguration,
        statusText: String,
        displayState: GeminiLiveConnectionState,
        preserveAudioSession: Bool = false
    ) {
        tearDownConnection(preserveAudioSession: preserveAudioSession)

        captureMode = .webRTC
        audioChunkCount = 0
        userInitiatedDisconnect = false
        hasCompletedSetup = false
        setupCompleteTime = nil
        modelHasSpoken = false
        isFirstModelTurn = true
        isResumingConnection = latestSessionHandle != nil

        guard let url = liveURL(apiKey: configuration.apiKey) else {
            onStateChange?(.failed, "Couldn't create the Gemini Live URL.")
            return
        }

        prepareOutputIfNeeded()

        let task = urlSession.webSocketTask(with: url)
        socketTask = task
        task.resume()
        onStateChange?(displayState, statusText)
        receiveNextMessage()
        sendSetup(using: configuration, displayState: displayState)
    }

    func tearDownConnection(preserveAudioSession: Bool = false) {
        hasCompletedSetup = false
        setupCompleteTime = nil
        cancelAudioCaptureMonitor()
        resetPlayback()
        modelHasSpoken = false
        isFirstModelTurn = true

        if preserveAudioSession, captureMode == .webRTC {
            guard let socketTask else { return }

            self.socketTask = nil
            socketTask.cancel(with: .normalClosure, reason: nil)
            return
        }

        stopMicrophone(notifyModel: false)
        teardownMicrophoneCapture()
        webRTCAudioIO?.stop()
        webRTCAudioIO = nil
        if outputEngine.isRunning {
            outputEngine.stop()
        }
        outputPrepared = false

        guard let socketTask else { return }

        self.socketTask = nil
        socketTask.cancel(with: .normalClosure, reason: nil)
    }

    func cancelPendingReconnect() {
        pendingReconnectWorkItem?.cancel()
        pendingReconnectWorkItem = nil
    }

    @discardableResult
    func scheduleAutomaticReconnect(
        after delay: TimeInterval,
        statusText: String,
        requireSafeResumptionHandle: Bool = false,
        preserveConnectedState: Bool = false,
        allowFreshReconnectWithoutHandle: Bool = false,
        preserveAudioSession: Bool = false
    ) -> Bool {
        guard !userInitiatedDisconnect,
              pendingReconnectWorkItem == nil,
              let currentConfiguration else {
            return false
        }

        if requireSafeResumptionHandle && (!latestSessionHandleIsResumable || latestSessionHandle == nil) {
            return false
        }

        if latestSessionHandle == nil && !allowFreshReconnectWithoutHandle {
            return false
        }

        let displayState: GeminiLiveConnectionState = preserveConnectedState ? .connected : .connecting
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReconnectWorkItem = nil
            guard !self.userInitiatedDisconnect else { return }

            self.startConnection(
                using: currentConfiguration,
                statusText: self.latestSessionHandle != nil ? "Resuming Gemini Live..." : "Reconnecting to Gemini Live...",
                displayState: displayState,
                preserveAudioSession: preserveAudioSession
            )
        }

        pendingReconnectWorkItem = workItem
        onStateChange?(displayState, statusText)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    func parseGoAwayTimeLeft(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("s") else { return nil }
        return Double(trimmed.dropLast())
    }

    func sendSetup(using configuration: LiveSessionConfiguration, displayState: GeminiLiveConnectionState) {
        var generationConfig: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": configuration.voiceName,
                    ],
                ],
            ],
        ]
        if configuration.thinkingBudget > 0 {
            generationConfig["thinkingConfig"] = ["thinkingBudget": configuration.thinkingBudget]
        }

        var setup: [String: Any] = [
            "model": "models/\(configuration.model)",
            "inputAudioTranscription": [:],
            "outputAudioTranscription": [:],
            "contextWindowCompression": [
                "slidingWindow": [:],
            ],
            "sessionResumption": latestSessionHandle.map { ["handle": $0] } ?? [:],
            "generationConfig": generationConfig,
            "realtimeInputConfig": [
                "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
                "automaticActivityDetection": [
                    "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_HIGH",
                    "prefixPaddingMs": 20,
                    "silenceDurationMs": 500,
                ],
            ],
            "tools": [
                [
                    "functionDeclarations": enabledToolDeclarations
                ]
            ],
        ]
        if let systemPrompt = configuration.systemPrompt {
            setup["systemInstruction"] = ["parts": [["text": systemPrompt]]]
        }

        sendJSONObject(["setup": setup]) { [weak self] success in
            guard let self, success else { return }

            self.onStateChange?(displayState, "Connected. Waiting for Gemini Live setup...")
        }
    }

    func sendJSONObject(_ object: [String: Any], onCompletion: (@Sendable (Bool) -> Void)? = nil) {
        guard let socketTask else { return }

        sendQueue.async { [weak self] in
            guard let self else { return }

            do {
                let data = try JSONSerialization.data(withJSONObject: object)
                guard let message = String(data: data, encoding: .utf8) else {
                    self.handleFailure(
                        message: "Couldn't encode the Gemini Live message.",
                        preserveAudioSession: self.hasCompletedSetup && self.captureMode == .webRTC
                    )
                    onCompletion?(false)
                    return
                }

                socketTask.send(.string(message)) { error in
                    if let error {
                        let hadCompletedSetup = self.hasCompletedSetup
                        let shouldPreserveAudioSession = hadCompletedSetup && self.captureMode == .webRTC
                        self.tearDownConnection(preserveAudioSession: shouldPreserveAudioSession)

                        if self.scheduleAutomaticReconnect(
                            after: 0.1,
                            statusText: self.latestSessionHandle != nil ? "Resuming Gemini Live session..." : "Reconnecting to Gemini Live...",
                            preserveConnectedState: hadCompletedSetup,
                            allowFreshReconnectWithoutHandle: !hadCompletedSetup,
                            preserveAudioSession: shouldPreserveAudioSession
                        ) {
                            onCompletion?(false)
                            return
                        }

                        self.handleFailure(
                            message: "Gemini Live send failed: \(error.localizedDescription)",
                            preserveAudioSession: hadCompletedSetup && self.captureMode == .webRTC
                        )
                        onCompletion?(false)
                    } else {
                        onCompletion?(true)
                    }
                }
            } catch {
                self.handleFailure(
                    message: "Couldn't prepare the Gemini Live payload.",
                    preserveAudioSession: self.hasCompletedSetup && self.captureMode == .webRTC
                )
                onCompletion?(false)
            }
        }
    }

    func receiveNextMessage() {
        guard let socketTask else { return }

        socketTask.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .failure(error):
                guard !self.userInitiatedDisconnect else { return }

                let hadCompletedSetup = self.hasCompletedSetup
                let shouldPreserveAudioSession = hadCompletedSetup && self.captureMode == .webRTC
                self.tearDownConnection(preserveAudioSession: shouldPreserveAudioSession)

                if self.pendingReconnectWorkItem != nil {
                    self.cancelPendingReconnect()
                    _ = self.scheduleAutomaticReconnect(
                        after: 0.1,
                        statusText: self.latestSessionHandle != nil ? "Resuming Gemini Live session..." : "Reconnecting to Gemini Live...",
                        preserveConnectedState: hadCompletedSetup,
                        allowFreshReconnectWithoutHandle: !hadCompletedSetup,
                        preserveAudioSession: shouldPreserveAudioSession
                    )
                    return
                }

                if self.scheduleAutomaticReconnect(
                    after: 0.35,
                    statusText: self.latestSessionHandle != nil ? "Resuming Gemini Live session..." : "Reconnecting to Gemini Live...",
                    preserveConnectedState: hadCompletedSetup,
                    allowFreshReconnectWithoutHandle: !hadCompletedSetup,
                    preserveAudioSession: shouldPreserveAudioSession
                ) {
                    return
                }

                self.handleFailure(
                    message: "Gemini Live disconnected: \(error.localizedDescription)",
                    preserveAudioSession: hadCompletedSetup && self.captureMode == .webRTC
                )
            case let .success(message):
                self.handleMessage(message)
                self.receiveNextMessage()
            }
        }
    }

    func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let rawData: Data?

        switch message {
        case let .string(text):
            rawData = text.data(using: .utf8)
        case let .data(data):
            rawData = data
        @unknown default:
            rawData = nil
        }

        guard
            let rawData,
            let object = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
        else {
            return
        }

        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "Gemini Live returned an unknown error."
            handleFailure(message: message, preserveAudioSession: hasCompletedSetup && captureMode == .webRTC)
            return
        }

        if let sessionResumptionUpdate = object["sessionResumptionUpdate"] as? [String: Any] {
            handleSessionResumptionUpdate(sessionResumptionUpdate)
        }

        if let goAway = object["goAway"] as? [String: Any] {
            handleGoAway(goAway)
        }

        if object.keys.contains("setupComplete") {
            handleSetupComplete()
        }

        if let toolCall = object["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                handleFunctionCall(call)
            }
        }

        guard let serverContent = object["serverContent"] as? [String: Any] else { return }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            resetPlayback()
        }

        if
            let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
            let text = inputTranscription["text"] as? String
        {
            onUserTranscript?(text)
        }

        if
            let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
            let text = outputTranscription["text"] as? String
        {
            onModelTranscript?(text)
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            if modelHasSpoken {
                isFirstModelTurn = false
            }
            onTurnComplete?()
        }

        if let generationComplete = serverContent["generationComplete"] as? Bool, generationComplete {
            // Docs: signals the model finished generating its response.
            // Audio playback may still be in progress at this point.
        }

        if
            let modelTurn = serverContent["modelTurn"] as? [String: Any],
            let parts = modelTurn["parts"] as? [[String: Any]]
        {
            modelHasSpoken = true
            for part in parts {
                guard
                    let inlineData = part["inlineData"] as? [String: Any],
                    let encodedAudio = inlineData["data"] as? String,
                    let decodedAudio = Data(base64Encoded: encodedAudio),
                    !decodedAudio.isEmpty
                else {
                    continue
                }

                enqueueOutputAudio(decodedAudio)
            }
        }
    }
}

struct LiveSessionConfiguration {
    let apiKey: String
    let model: String
    let systemPrompt: String?
    let thinkingBudget: Int
    let voiceName: String
    let braveSearchAPIKey: String?
    let skillSnapshot: SkillSessionSnapshot?
}
