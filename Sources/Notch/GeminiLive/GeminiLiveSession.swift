@preconcurrency import AVFoundation
import Foundation

// Internal to this module - used by GeminiLiveSession and its extensions
enum GeminiLiveCaptureMode {
    case webRTC
    case voiceProcessing
    case standard
}

final class GeminiLiveSession: @unchecked Sendable {
    var onStateChange: (@Sendable (GeminiLiveConnectionState, String?) -> Void)?
    var onUserTranscript: (@Sendable (String) -> Void)?
    var onModelTranscript: (@Sendable (String) -> Void)?
    var onTurnComplete: (@Sendable () -> Void)?
    var onTimerControl: (@Sendable (_ timer: String, _ action: String, _ duration: String?, _ breakDuration: String?, _ minutes: Int?, _ breakMinutes: Int?) -> String)?
    var onMediaControl: (@Sendable (_ action: String, _ value: Double?, _ valueString: String?) -> String)?
    var onFunctionExecuted: (@Sendable (_ name: String, _ args: [String: Any], _ result: [String: Any]) -> Void)?
    var onDisplayImageRequest: (@Sendable (ImageOverlayRequest) -> Void)?

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

    let urlSession = URLSession(configuration: .default)
    let pexelsSession = URLSession(configuration: .ephemeral)
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
    var enabledTools: Set<GeminiTool> = Set(GeminiTool.allCases)
    var microphoneEnabled = true
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
        pexelsAPIKey: String? = nil,
        braveSearchAPIKey: String? = nil,
        enabledTools: Set<GeminiTool> = Set(GeminiTool.allCases),
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
            pexelsAPIKey: pexelsAPIKey,
            braveSearchAPIKey: braveSearchAPIKey
        )
        currentConfiguration = configuration

        startConnection(
            using: configuration,
            statusText: resumeSession && latestSessionHandle != nil ? "Resuming Gemini Live..." : "Connecting to Gemini Live...",
            displayState: resumeSession && latestSessionHandle != nil ? .connected : .connecting
        )
    }

    func disconnect(userInitiated: Bool) {
        userInitiatedDisconnect = userInitiated
        cancelPendingReconnect()

        if userInitiated {
            currentConfiguration = nil
            latestSessionHandle = nil
            latestSessionHandleIsResumable = false
        }

        tearDownConnection()

        if userInitiated {
            isResumingConnection = false
            onStateChange?(.disconnected, "Disconnected.")
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

    func liveURL(apiKey: String) -> URL? {
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
        ]
        return components?.url
    }

    var enabledToolDeclarations: [[String: Any]] {
        var decls: [[String: Any]] = []
        if enabledTools.contains(.controlApp) {
            decls.append([
                "name": "controlApp",
                "description": "Control an application on the user's macOS computer. You can open or close applications by their name. If the user asks to open something like Youtube, you might open a browser like Safari or Chrome.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "appName": [
                            "type": "STRING",
                            "description": "The name of the application, e.g. Safari, Mail, Terminal, Spotify, etc."
                        ],
                        "action": [
                            "type": "STRING",
                            "enum": ["open", "close"],
                            "description": "The action to perform: 'open' or 'close'."
                        ]
                    ],
                    "required": ["appName", "action"]
                ]
            ])
        }
        if enabledTools.contains(.controlBrowser) {
            decls.append([
                "name": "controlBrowser",
                "description": "Control browser tabs on macOS. Automatically uses the user's default browser (Chrome, Safari, Firefox, Edge). You can open a link, or open the top DuckDuckGo Lucky result for a search query, close a tab, switch tab, list tabs, reload, or read the current page's content. For music requests, prefer action='open' with query.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "enum": ["open", "close", "list", "switch", "reload", "read"],
                            "description": "The action. 'read' extracts text from the active tab."
                        ],
                        "url": [
                            "type": "STRING",
                            "description": "The URL to open for action='open' when an exact link is already known."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For action='open', a search query that should open the top DuckDuckGo Lucky result. Use this for music/song requests. For action='close' and action='switch', this is a title or URL fragment to identify the tab."
                        ]
                    ],
                    "required": ["action"]
                ]
            ])
        }
        if enabledTools.contains(.controlTimer) {
            decls.append([
                "name": "controlTimer",
                "description": "Control the built-in focus timers in the Notch app. Use this when the user asks to start, stop, pause, resume or reset the Pomodoro, Countdown or Stopwatch.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "timer": [
                            "type": "STRING",
                            "enum": ["pomodoro", "countdown", "stopwatch"],
                            "description": "Which timer to control."
                        ],
                        "action": [
                            "type": "STRING",
                            "enum": ["start", "pause", "resume", "reset", "skip"],
                            "description": "Action: 'start', 'pause', 'resume', 'reset', or 'skip' (Pomodoro only)."
                        ],
                        "duration": [
                            "type": "STRING",
                            "description": "Optional. Duration as a human string, e.g. '25m', '1h30m', '90s', '1h 30m 15s'. For Pomodoro this is the focus duration. For Countdown this is the timer length. Defaults to 25m for Pomodoro, 10m for Countdown."
                        ],
                        "breakDuration": [
                            "type": "STRING",
                            "description": "Optional. Break duration for Pomodoro as a human string, e.g. '5m', '10m'. Defaults to 5m."
                        ],
                        "minutes": [
                            "type": "NUMBER",
                            "description": "Optional. Legacy numeric focus minutes (prefer 'duration' string instead)."
                        ],
                        "breakMinutes": [
                            "type": "NUMBER",
                            "description": "Optional. Legacy numeric break minutes (prefer 'breakDuration' string instead)."
                        ]
                    ],
                    "required": ["timer", "action"]
                ]
            ])
        }
        if enabledTools.contains(.controlMedia) {
            decls.append([
                "name": "controlMedia",
                "description": "Control media playback (music, podcast, etc.) on the user's Mac.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "enum": ["play", "pause", "stop", "toggle", "next", "previous", "skip_forward", "skip_backward", "volume", "shuffle", "repeat", "favorite"],
                            "description": "Media action. 'favorite' toggles loved state (Apple Music only). 'stop' sends system stop command."
                        ],
                        "value": [
                            "type": "NUMBER",
                            "description": "Optional. For 'volume': 0-100. For 'skip_*': seconds as a number (default 15)."
                        ],
                        "valueString": [
                            "type": "STRING",
                            "description": "Optional. For 'skip_forward'/'skip_backward': duration as a string, e.g. '30s', '1m'. Takes priority over 'value'."
                        ]
                    ],
                    "required": ["action"]
                ]
            ])
        }
        if enabledTools.contains(.readClipboard) {
            decls.append([
                "name": "readClipboard",
                "description": "Read the current text content from the user's macOS clipboard (pasteboard). Use this when the user asks you to summarize, translate, read or process the text they just copied.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:],
                    "required": []
                ]
            ])
        }
        if enabledTools.contains(.manageNotes) {
            decls.append([
                "name": "manageNotes",
                "description": "Manage user's macOS Notes and Reminders. You can use this to quickly write down a note, create a reminder or to-do list item.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "enum": ["add_note", "add_reminder"],
                            "description": "Action to perform: 'add_note' or 'add_reminder'."
                        ],
                        "content": [
                            "type": "STRING",
                            "description": "Content of the note or the reminder."
                        ],
                        "title": [
                            "type": "STRING",
                            "description": "Optional title for the note (if creating a note)."
                        ]
                    ],
                    "required": ["action", "content"]
                ]
            ])
        }
        if enabledTools.contains(.controlVolume) {
            decls.append([
                "name": "controlVolume",
                "description": "Control the macOS system volume. Can set volume level, get current volume, mute or unmute.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "enum": ["set", "get", "mute", "unmute"],
                            "description": "Action: 'set' to set volume level, 'get' to read it, 'mute' to mute, 'unmute' to unmute."
                        ],
                        "level": [
                            "type": "NUMBER",
                            "description": "Volume level 0–100. Required when action is 'set'."
                        ]
                    ],
                    "required": ["action"]
                ]
            ])
        }
        if enabledTools.contains(.displayImage) {
            decls.append([
                "name": "displayImage",
                "description": "Search Pexels and show a small image above the live transcript; visibility matches the transcript overlay timing.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "query": [
                            "type": "STRING",
                            "description": "A short descriptive query for the image to show."
                        ],
                        "caption": [
                            "type": "STRING",
                            "description": "Optional caption (for tool result metadata)."
                        ],
                        "orientation": [
                            "type": "STRING",
                            "enum": ["landscape", "portrait", "square"],
                            "description": "Optional preferred orientation. Use landscape unless the user asks for portrait or square."
                        ]
                    ],
                    "required": ["query"]
                ]
            ])
        }
        if enabledTools.contains(.webSearch) {
            decls.append([
                "name": "webSearch",
                "description": "Search the web using DuckDuckGo and return a concise summary of the top results. Use this when the user asks a question that requires up-to-date information or facts you may not know.",
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
                    self.handleFailure(message: "Couldn't encode the Gemini Live message.")
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

                        self.handleFailure(message: "Gemini Live send failed: \(error.localizedDescription)")
                        onCompletion?(false)
                    } else {
                        onCompletion?(true)
                    }
                }
            } catch {
                self.handleFailure(message: "Couldn't prepare the Gemini Live payload.")
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

                self.handleFailure(message: "Gemini Live disconnected: \(error.localizedDescription)")
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
            handleFailure(message: message)
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
    let pexelsAPIKey: String?
    let braveSearchAPIKey: String?
}
