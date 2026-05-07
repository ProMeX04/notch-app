@preconcurrency import AVFoundation
import Foundation
import NotchTooling

struct PendingExecApprovalCall {
    let toolCallID: String
    let args: [String: Any]
    let command: String
    let workingDirectory: String?
    let timeoutSeconds: Double
}

// Internal to this module - used by GeminiLiveSession and its extensions
enum GeminiLiveCaptureMode {
    case webRTC
    case voiceProcessing
    case standard
}

struct GeminiLiveUsageMetadata: Sendable {
    let promptTokenCount: Int
    let responseTokenCount: Int
    let totalTokenCount: Int

    static let zero = GeminiLiveUsageMetadata(
        promptTokenCount: 0,
        responseTokenCount: 0,
        totalTokenCount: 0
    )

    init(promptTokenCount: Int, responseTokenCount: Int, totalTokenCount: Int) {
        self.promptTokenCount = promptTokenCount
        self.responseTokenCount = responseTokenCount
        self.totalTokenCount = totalTokenCount
    }

    init(dictionary: [String: Any]) {
        let prompt = Self.intValue(for: ["promptTokenCount"], in: dictionary) ?? 0
        let response = Self.intValue(
            for: ["responseTokenCount", "candidatesTokenCount", "outputTokenCount"],
            in: dictionary
        ) ?? 0
        let total = Self.intValue(for: ["totalTokenCount"], in: dictionary) ?? max(prompt + response, prompt)

        self.init(
            promptTokenCount: prompt,
            responseTokenCount: response,
            totalTokenCount: total
        )
    }

    var currentContextTokenCount: Int {
        max(promptTokenCount, totalTokenCount)
    }

    private static func intValue(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            guard let rawValue = dictionary[key] else { continue }
            if let number = rawValue as? NSNumber {
                return number.intValue
            }
            if let string = rawValue as? String, let intValue = Int(string) {
                return intValue
            }
        }
        return nil
    }
}

final class GeminiLiveSession: @unchecked Sendable {
    static let defaultContextWindowTargetTokens = 25_000
    static let defaultContextWindowTriggerTokens = 65_000
    private static let setupCompletionTimeout: TimeInterval = 15.0
    private static let maxReconnectDelay: TimeInterval = 30.0
    private static let baseReconnectDelay: TimeInterval = 0.5
    private static let pingInterval: DispatchTimeInterval = .seconds(20)
    private static let pingTimeout: TimeInterval = 10.0
    private static let heartbeatWatchdogInterval: TimeInterval = 40.0

    var onStateChange: (@Sendable (GeminiLiveConnectionState, String?) -> Void)?
    var onUserTranscript: (@Sendable (String) -> Void)?
    var onModelTranscript: (@Sendable (String) -> Void)?
    var onTurnComplete: (@Sendable () -> Void)?
    var onModelThinkingStateChange: (@Sendable (Bool) -> Void)?
    var onMicrophoneInputLevel: (@Sendable (Double) -> Void)?
    var onMicrophoneCaptureStateChange: (@Sendable (Bool) -> Void)?
    var onReconnectStateChange: (@Sendable (GeminiLiveReconnectState) -> Void)?
    var onUsageMetadata: (@Sendable (GeminiLiveUsageMetadata) -> Void)?
    var onFunctionStarted: (@Sendable (_ name: String, _ args: [String: Any]) -> Void)?
    var onFunctionExecuted: (@Sendable (_ name: String, _ args: [String: Any], _ result: [String: Any]) -> Void)?
    var onShouldAutoApproveExec: (@Sendable (_ command: String, _ workingDirectory: String?) -> Bool)?
    var onExecApprovalRequested: (@Sendable (ExecApprovalRequest) -> Void)?

    /// Intercept handler for `notchctl` URL-scheme commands (media, focus, talk, panel, etc.).
    /// Returns `true` if the command was handled in-process, `false` to fall through to shell.
    var onNotchCommand: (@Sendable (String) async -> Bool)?
    var onReadPomodoroState: (@Sendable () async -> [String: Any])?
    var onReadMediaState: (@Sendable () async -> [String: Any])?
    var onMediaCommand: (@Sendable (String, [String: String]) async -> Bool)?
    var onReadUserStore: (@Sendable () -> String)?
    var onReadMemoryStore: (@Sendable () -> String)?
    var onWriteUserStore: (@Sendable (_ content: String) async -> Bool)?
    var onWriteMemoryStore: (@Sendable (_ content: String) async -> Bool)?

    /// Send a browser command through the extension bridge.
    /// Returns the result dict if the extension responded, or nil on timeout.
    var onBrowserBridgeCommand: (@Sendable (_ action: String, _ args: [String: Any]) async -> [String: Any]?)?

    /// Check if the browser extension is currently connected and polling.
    var onBrowserBridgeIsConnected: (@Sendable () -> Bool)?

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
    /// Shared ephemeral session for Brave search and other tool HTTP.
    let toolHTTPURLSession = URLSession(configuration: .ephemeral)
    let sendQueue = DispatchQueue(label: "dev.notch.gemini.send")
    let toolExecutionQueue = DispatchQueue(label: "dev.notch.gemini.tool-execution", qos: .userInitiated)
    let audioProcessingQueue = DispatchQueue(label: "dev.notch.gemini.capture")
    let playbackQueue = DispatchQueue(label: "dev.notch.gemini.playback")
    /// Serial queue for all blocking CoreAudio / WebRTC lifecycle work
    /// (factory init, playout/record start & stop, engine stop, tap removal).
    /// Keeping these off the caller thread prevents UI stutter when the user
    /// presses Connect / Disconnect from the main thread.
    let audioLifecycleQueue = DispatchQueue(label: "dev.notch.gemini.audio-lifecycle", qos: .userInitiated)

    let outputEngine = AVAudioEngine()
    let outputPlayer = AVAudioPlayerNode()
    let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )

    var standardInputEngine: AVAudioEngine?
    var inputConverter: AVAudioConverter?
    var audioConversionConsecutiveFailures = 0
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
    )

    var socketTask: URLSessionWebSocketTask?
    var enabledTools: Set<GeminiTool> = GeminiTool.coreToolSet
    var microphoneEnabled = false
    var microphonePrewarmingEnabled = false
    var outputVolume: Float = 1
    var outputPrepared = false
    var allowModelAudioPlayback = true
    var userInitiatedDisconnect = false
    var hasCompletedSetup = false
    var setupCompleteTime: Date?
    var isResumingConnection = false
    var currentConfiguration: LiveSessionConfiguration?
    var latestSessionHandle: String?
    var latestSessionHandleIsResumable = false
    var pendingReconnectWorkItem: DispatchWorkItem?
    var setupTimeoutWorkItem: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private var lastMessageReceivedAt: Date?
    private var reconnectAttemptCount = 0
    private var hasLoggedUnstableConnection = false
    private let execApprovalQueue = DispatchQueue(label: "dev.notch.gemini.exec-approval")
    private var pendingExecApprovalsByID: [String: PendingExecApprovalCall] = [:]

    var currentResumptionHandle: String? {
        guard latestSessionHandleIsResumable else { return nil }
        guard let latestSessionHandle, !latestSessionHandle.isEmpty else { return nil }
        return latestSessionHandle
    }

    deinit {
        disconnect(userInitiated: true)
    }

    var isLocalWebRTCMicrophoneCaptureActive: Bool {
        captureMode == .webRTC &&
            webRTCAudioIO?.isCapturing == true
    }

    func connect(
        connectionCredential: String,
        restAPIKey: String? = nil,
        backendConfiguration: GeminiLiveBackendConfiguration? = nil,
        model: String,
        systemPrompt: String?,
        microphoneEnabled: Bool,
        microphonePrewarmingEnabled: Bool = false,
        thinkingBudget: Int,
        voiceName: String = "Kore",
        enabledTools: Set<GeminiTool> = GeminiTool.coreToolSet,
        skillSnapshot: SkillSessionSnapshot? = nil,
        resumeSession: Bool = false
    ) {
        cancelPendingReconnect()

        self.enabledTools = enabledTools
        self.microphoneEnabled = microphoneEnabled
        self.microphonePrewarmingEnabled = microphonePrewarmingEnabled
        onUsageMetadata?(.zero)

        if !resumeSession {
            latestSessionHandle = nil
            latestSessionHandleIsResumable = false
        }

        let configuration = LiveSessionConfiguration(
            connectionCredential: connectionCredential,
            restAPIKey: restAPIKey,
            backendConfiguration: backendConfiguration,
            model: model,
            systemPrompt: systemPrompt,
            thinkingBudget: thinkingBudget,
            voiceName: voiceName,
            skillSnapshot: skillSnapshot
        )
        currentConfiguration = configuration
        let shouldPreserveAudioSession = outputPrepared && captureMode == .webRTC

        startConnection(
            using: configuration,
            statusText: resumeSession && currentResumptionHandle != nil ? "Resuming Gemini Live..." : "Connecting to Gemini Live...",
            displayState: resumeSession && currentResumptionHandle != nil ? .connected : .connecting,
            preserveAudioSession: shouldPreserveAudioSession
        )
    }

    func disconnect(userInitiated: Bool) {
        userInitiatedDisconnect = userInitiated
        cancelPendingReconnect()
        cancelSetupTimeout()
        stopHeartbeat()
        onReconnectStateChange?(.none)
        onMicrophoneInputLevel?(0)
        onMicrophoneCaptureStateChange?(false)
        onUsageMetadata?(.zero)

        if userInitiated {
            currentConfiguration = nil
            latestSessionHandle = nil
            latestSessionHandleIsResumable = false
            reconnectAttemptCount = 0
            hasLoggedUnstableConnection = false
            clearPendingExecApprovals()
            isResumingConnection = false
            // Fire the disconnected state right away so the UI button/label
            // updates instantly even if the audio stack is still winding down.
            onStateChange?(.disconnected, "Disconnected.")
        }

        // Cancel the socket synchronously so no more receive/send callbacks
        // fire against this session, and clear fast state flags.
        let pendingSocket = socketTask
        socketTask = nil
        hasCompletedSetup = false
        setupCompleteTime = nil
        cancelAudioCaptureMonitor()
        resetPlayback()
        pendingSocket?.cancel(with: .normalClosure, reason: nil)

        // Heavy CoreAudio / WebRTC teardown goes to the serial queue so the
        // caller (usually the main thread on user disconnect) never blocks.
        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            // If a concurrent startConnection block ran between the sync
            // `socketTask = nil` above and this point, it may have installed
            // a fresh socket. Cancel it too while we're still in a
            // user-initiated disconnect.
            if self.userInitiatedDisconnect, let lingeringSocket = self.socketTask {
                self.socketTask = nil
                lingeringSocket.cancel(with: .normalClosure, reason: nil)
            }
            self.stopMicrophone(notifyModel: false)
            self.teardownMicrophoneCapture()
            self.webRTCAudioIO?.stop()
            self.webRTCAudioIO = nil
            if self.outputEngine.isRunning {
                self.outputEngine.stop()
            }
            self.outputPrepared = false
        }
    }


    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneEnabled = enabled

        guard socketTask != nil else { return }

        // Starting/stopping CoreAudio or WebRTC capture can block briefly.
        // Run the heavy lifecycle work off the caller thread so mic toggles
        // from SwiftUI controls do not hitch the notch animation.
        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            guard self.socketTask != nil else { return }
            guard self.microphoneEnabled == enabled else { return }

            if self.captureMode == .webRTC, let webRTCAudioIO = self.webRTCAudioIO {
                if enabled {
                    webRTCAudioIO.setMicrophoneMuted(false)
                    self.startMicrophone()
                } else {
                    self.cancelAudioCaptureMonitor()
                    self.sendJSONObject([
                        "realtimeInput": [
                            "audioStreamEnd": true,
                        ],
                    ])
                    if self.microphonePrewarmingEnabled {
                        self.startPrewarmedMicrophoneIfNeeded()
                    } else {
                        self.onMicrophoneCaptureStateChange?(false)
                        webRTCAudioIO.stopCapture()
                    }
                }
                return
            }

            if enabled {
                self.startMicrophone()
            } else {
                self.stopMicrophone(notifyModel: true)
                self.cancelAudioCaptureMonitor()
            }
        }
    }

    func setMicrophonePrewarmingEnabled(_ enabled: Bool) {
        microphonePrewarmingEnabled = enabled

        guard socketTask != nil else { return }

        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            guard self.socketTask != nil else { return }
            guard self.microphonePrewarmingEnabled == enabled else { return }
            guard self.setupCompleteTime != nil else { return }
            guard self.captureMode == .webRTC else { return }

            if enabled {
                guard !self.microphoneEnabled else { return }
                self.startPrewarmedMicrophoneIfNeeded()
            } else {
                guard !self.microphoneEnabled else { return }
                guard let audioIO = self.webRTCAudioIO, audioIO.isCapturing else { return }
                audioIO.stopCapture()
                self.onMicrophoneCaptureStateChange?(false)
            }
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

    func interruptModelPlayback() {
        allowModelAudioPlayback = false
        resetPlayback()
    }

    func resumeModelPlayback() {
        allowModelAudioPlayback = true
    }

    func liveURLRequest(connectionCredential: String) -> URLRequest? {
        let trimmedCredential = connectionCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCredential.isEmpty else { return nil }

        let isEphemeralToken = trimmedCredential.hasPrefix("auth_tokens/")
        let apiVersion = isEphemeralToken ? "v1alpha" : "v1beta"
        let method = isEphemeralToken ? "BidiGenerateContentConstrained" : "BidiGenerateContent"
        let queryName = isEphemeralToken ? "access_token" : "key"

        var components = URLComponents(
            string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.\(apiVersion).GenerativeService.\(method)"
        )
        components?.queryItems = [
            URLQueryItem(name: queryName, value: trimmedCredential),
        ]
        guard let url = components?.url else { return nil }
        return URLRequest(url: url)
    }

    var enabledToolDeclarations: [[String: Any]] {
        var decls: [[String: Any]] = []
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
                "description": GeminiWorkspaceCodingTools.openClawReadToolDescription,
                "parameters": GeminiWorkspaceCodingTools.openClawReadToolParameters
            ])
        }
        if enabledTools.contains(.ls) {
            decls.append([
                "name": "ls",
                "description": GeminiWorkspaceCodingTools.openClawLsToolDescription,
                "parameters": GeminiWorkspaceCodingTools.openClawLsToolParameters
            ])
        }
        if enabledTools.contains(.calendar) {
            decls.append([
                "name": "calendar",
                "description": """
                Manage the user's macOS Calendar (iCloud, Google, Exchange, etc.).
                Actions:
                - "list": Query events. Params: daysAhead (0-30, default 0), daysBack (0-30, default 0), query (filter by title).
                - "create": Create a new event. Params: title (required), startDate (required, 'yyyy-MM-dd HH:mm'), endDate (optional), allDay (bool), location, notes, calendarName, alertMinutesBefore (set a notification alert).
                - "delete": Delete an event. Params: eventId (required, from list results).
                - "calendars": List all available calendars and their properties.
                - "list_reminders": List pending or completed reminders (to-do items). Params: query, isCompleted, reminderList.
                - "create_reminder": Create a new reminder/to-do. Params: title (required), notes, reminderList, startDate (due date/time — the notification fires exactly at this time by default), alertMinutesBefore (only set if user explicitly asks to be reminded BEFORE the due time; defaults to 0 = alert at due time).
                - "complete_reminder": Mark a reminder as completed. Params: eventId (required).
                - "delete_reminder": Delete a reminder. Params: eventId (required).
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'list', 'create', 'delete', 'calendars', 'list_reminders', 'create_reminder', 'complete_reminder', or 'delete_reminder'."
                        ],
                        "daysAhead": [
                            "type": "NUMBER",
                            "description": "For 'list': days into the future (0-30). Default 0."
                        ],
                        "daysBack": [
                            "type": "NUMBER",
                            "description": "For 'list': days into the past (0-30). Default 0."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'list' or 'list_reminders': filter by text."
                        ],
                        "title": [
                            "type": "STRING",
                            "description": "For 'create': event title (required)."
                        ],
                        "startDate": [
                            "type": "STRING",
                            "description": "For 'create': start date/time in 'yyyy-MM-dd HH:mm' format (required). For 'create_reminder': the due date."
                        ],
                        "endDate": [
                            "type": "STRING",
                            "description": "For 'create': end date/time. Defaults to 1 hour after start."
                        ],
                        "allDay": [
                            "type": "BOOLEAN",
                            "description": "For 'create': true for all-day events."
                        ],
                        "location": [
                            "type": "STRING",
                            "description": "For 'create': event location."
                        ],
                        "notes": [
                            "type": "STRING",
                            "description": "For 'create': event notes/description."
                        ],
                        "calendarName": [
                            "type": "STRING",
                            "description": "For 'create': target calendar name. Defaults to the user's default calendar."
                        ],
                        "eventId": [
                            "type": "STRING",
                            "description": "For 'delete': the event ID from 'list' results."
                        ],
                        "alertMinutesBefore": [
                            "type": "NUMBER",
                            "description": "For 'create': minutes before the event to show a notification. For 'create_reminder': defaults to 0 (alert fires at the due time). Only set a non-zero value if the user explicitly asks to be reminded BEFORE the due time."
                        ],
                        "reminderList": [
                            "type": "STRING",
                            "description": "For 'create_reminder' or 'list_reminders': target reminder list name (e.g., 'Groceries', 'Inbox'). Defaults to default list."
                        ],
                        "isCompleted": [
                            "type": "BOOLEAN",
                            "description": "For 'list_reminders': true to show completed, false for pending (default)."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.clipboard) {
            decls.append([
                "name": "clipboard",
                "description": """
                Read or write the macOS system clipboard, or copy file references to it.
                Actions:
                - "read": Return the current clipboard text.
                - "write": Copy plain text to the clipboard for pasting elsewhere (Cmd+V). Use this for normal "copy this" requests.
                - "copy-file": Copy one or more file references to the clipboard so the user can paste them into Finder, Mail, Slack, etc. as attachments. Use this only when the user explicitly wants the file itself pasted, not the file's text contents.
                Treat clipboard text as potentially sensitive. Tell the user briefly what was placed on the clipboard.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'read', 'write', or 'copy-file'."
                        ],
                        "text": [
                            "type": "STRING",
                            "description": "For 'write': the text to copy to the clipboard."
                        ],
                        "paths": [
                            "type": "ARRAY",
                            "items": ["type": "STRING"],
                            "description": "For 'copy-file': one or more file paths to copy as file references."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.appControl) {
            decls.append([
                "name": "appControl",
                "description": """
                Control macOS application windows: open, quit, check running state, minimize, or move/position a window.
                Actions:
                - "open": Launch an app by name.
                - "quit": Quit an app by name.
                - "check": Check whether an app is currently running.
                - "minimize": Minimize the front window of an app.
                - "move": Move and resize the front window to a screen position (left, right, top, bottom, center).
                Use exact app names like Safari, Spotify, Notes. Do not use this for opening URLs or websites.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'open', 'quit', 'check', 'minimize', or 'move'."
                        ],
                        "appName": [
                            "type": "STRING",
                            "description": "The exact macOS application name, e.g. 'Safari', 'Spotify', 'Notes'."
                        ],
                        "direction": [
                            "type": "STRING",
                            "description": "For 'move': the target position — 'left', 'right', 'top', 'bottom', or 'center'."
                        ],
                    ],
                    "required": ["action", "appName"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.mediaControl) {
            decls.append([
                "name": "mediaControl",
                "description": """
                Control media playback and system volume on the user's Mac.
                Playback actions: play, pause, toggle, next, previous, stop, skip-forward, skip-backward, open.
                Volume actions: volume-get, volume-set, mute, unmute.
                Use 'status' to check what is currently playing (title, artist, album, playing state, volume).
                All actions return the current media state after execution.
                If no supported media app is running, say so clearly instead of guessing.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'status', 'play', 'pause', 'toggle', 'next', 'previous', 'stop', 'skip-forward', 'skip-backward', 'open', 'volume-get', 'volume-set', 'mute', 'unmute'."
                        ],
                        "volumeLevel": [
                            "type": "NUMBER",
                            "description": "For 'volume-set': volume level 0-100 (e.g. 100 for maximum, 50 for half)."
                        ],
                        "skipSeconds": [
                            "type": "NUMBER",
                            "description": "For 'skip-forward'/'skip-backward': number of seconds to skip (e.g. 30)."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }

        if enabledTools.contains(.pomodoro) {
            decls.append([
                "name": "pomodoro",
                "description": """
                Control the Notch Pomodoro timer: start, pause, resume, reset, skip phase, check status.
                Use 'status' to query the current timer state.
                When the user asks to stop, end, cancel, or terminate a focus session, use the 'reset' action.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'status', 'start', 'pause', 'resume', 'reset', 'skip'. Use 'reset' when the user asks to stop, end, cancel, or terminate the active focus session."
                        ],
                        "focusDuration": [
                            "type": "STRING",
                            "description": "Focus duration, e.g. '25m' or '50m'. For 'start'."
                        ],
                        "breakDuration": [
                            "type": "STRING",
                            "description": "Short break duration, e.g. '5m'. For 'start'."
                        ],
                        "longBreakDuration": [
                            "type": "STRING",
                            "description": "Long break duration, e.g. '15m'. For 'start'."
                        ],
                        "cycleCount": [
                            "type": "NUMBER",
                            "description": "Number of focus sessions before a long break, e.g. 4. For 'start'."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.browserControl) {
            decls.append([
                "name": "browserControl",
                "description": """
                Control the browser: open URLs, read tab content, navigate, manage tabs, and interact with page elements.
                Actions:
                - "open": Open a URL in the default browser.
                - "lucky": Open the top DuckDuckGo search result. 'youtube' is appended automatically for music queries.
                - "read-tab": Read the current tab's URL, title, and visible text.
                - "navigate": Navigate the current tab to a URL (stays in same tab).
                - "go-back": Go back in browser history.
                - "go-forward": Go forward in browser history.
                - "reload": Reload the current page.
                - "close-tab": Close a tab. IMPORTANT: Use 'tabId' for a specific tab from 'list-tabs' results. If no 'tabId' is provided, the current active tab is closed.
                - "list-tabs": List all tabs in the front window. Returns each tab's unique 'tabId', title, and URL.
                - "switch-tab": Switch to a tab. IMPORTANT: Prefer 'tabId' for reliability. Using 'index' (1-based) is supported but discouraged as indices shift when tabs are moved or closed.
                - "scroll": Scroll the page up or down by a pixel amount (Chrome/Edge: precise; Safari: page scroll).
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'open', 'lucky', 'read-tab', 'navigate', 'go-back', 'go-forward', 'reload', 'close-tab', 'list-tabs', 'switch-tab', or 'scroll'."
                        ],
                        "url": [
                            "type": "STRING",
                            "description": "For 'open', 'navigate': the URL."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'lucky': the search query."
                        ],
                        "tabId": [
                            "type": "INTEGER",
                            "description": "The unique ID of the tab to target. Get this from 'list-tabs'. Highly recommended for 'close-tab', 'switch-tab', 'read-tab', and 'navigate'."
                        ],
                        "index": [
                            "type": "INTEGER",
                            "description": "For 'switch-tab': 1-based tab index. Discouraged, use 'tabId' instead."
                        ],
                        "direction": [
                            "type": "STRING",
                            "description": "For 'scroll': 'up' or 'down'. Defaults to 'down'."
                        ],
                        "amount": [
                            "type": "INTEGER",
                            "description": "For 'scroll': pixel amount to scroll. Defaults to 500."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.memory) {
            decls.append([
                "name": "memory",
                "description": """
                Read or write persistent memory files for long-term context.
                - "read-user": Read USER.md (stable identity: name, pronouns, role, preferences).
                - "read-memory": Read MEMORY.md (durable facts, preferences, habits).
                - "write-user": Overwrite USER.md with updated profile content.
                - "write-memory": Overwrite MEMORY.md with updated memory content.
                Use "write-user" when the user shares or corrects identity details. Use "write-memory" for broader long-term notes. Do not save temporary chatter or sensitive data.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "Action: 'read-user', 'read-memory', 'write-user', or 'write-memory'."
                        ],
                        "content": [
                            "type": "STRING",
                            "description": "For 'write-user' or 'write-memory': the full file content to save."
                        ],
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.localFileSearch) {
            decls.append([
                "name": "localFileSearch",
                "description": "Search indexed local files, folders, apps, and media on the user's Mac.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "query": [
                            "type": "STRING",
                            "description": "Search text."
                        ],
                        "limit": [
                            "type": "INTEGER",
                            "description": "Max results (default 10, max 50)."
                        ],
                        "scope": [
                            "type": "STRING",
                            "description": "Optional: 'home', 'documents', 'desktop', 'downloads', 'applications', or 'all'."
                        ],
                        "kind": [
                            "type": "STRING",
                            "description": "Optional: 'any', 'app', 'folder', 'document', 'image', 'pdf', 'audio', or 'video'."
                        ],
                    ],
                    "required": ["query"]
                ] as [String: Any]
            ])
        }
        if enabledTools.contains(.appleMail) {
            decls.append([
                "name": "appleMail",
                "description": """
                Search or list recent emails from Apple Mail.
                Actions:
                - "list_recent": List the most recent emails.
                - "search": Search for emails by keyword (sender name, email, subject, or snippet).
                - "read_content": Read the full content of a specific email.
                Requires Full Disk Access to read the Mail database.
                """,
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "action": [
                            "type": "STRING",
                            "description": "The action to perform: 'list_recent', 'search', or 'read_content'."
                        ],
                        "query": [
                            "type": "STRING",
                            "description": "For 'search': the search keyword. For 'read_content': the subject or sender to identify the email."
                        ],
                        "limit": [
                            "type": "NUMBER",
                            "description": "Max number of results to return (default 10)."
                        ],
                        "messageId": [
                            "type": "STRING",
                            "description": "For 'read_content': Optional database ID of the message."
                        ]
                    ],
                    "required": ["action"]
                ] as [String: Any]
            ])
        }
        return decls
    }

    var liveSetupTools: [[String: Any]] {
        var tools: [[String: Any]] = []

        if enabledTools.contains(.webSearch) {
            tools.append([
                "google_search": [:]
            ])
        }

        if !enabledToolDeclarations.isEmpty {
            tools.append([
                "functionDeclarations": enabledToolDeclarations
            ])
        }

        return tools
    }

    func startConnection(
        using configuration: LiveSessionConfiguration,
        statusText: String,
        displayState: GeminiLiveConnectionState,
        preserveAudioSession: Bool = false
    ) {
        // Fast state updates on the caller thread so the UI can reflect
        // "Connecting..." immediately, before any heavy audio work runs.
        captureMode = .webRTC
        audioChunkCount = 0
        cancelSetupTimeout()
        userInitiatedDisconnect = false
        hasCompletedSetup = false
        setupCompleteTime = nil
        isResumingConnection = currentResumptionHandle != nil

        guard let request = liveURLRequest(connectionCredential: configuration.connectionCredential) else {
            onStateChange?(.failed, "Couldn't create the Gemini Live URL.")
            return
        }

        onStateChange?(displayState, statusText)

        // Dispatch the blocking portion (CoreAudio / WebRTC init, WebSocket
        // creation, initial setup send) to a serial background queue. The
        // queue also serializes with teardown so new connects always see
        // a clean audio stack.
        audioLifecycleQueue.async { [weak self] in
            guard let self else { return }
            guard !self.userInitiatedDisconnect else { return }

            self.tearDownConnection(preserveAudioSession: preserveAudioSession)
            self.prepareOutputIfNeeded()

            let task = self.urlSession.webSocketTask(with: request)
            self.socketTask = task
            task.resume()
            self.scheduleSetupTimeout(for: task)
            self.receiveNextMessage()
            self.sendSetup(using: configuration, displayState: displayState)
        }
    }

    func tearDownConnection(preserveAudioSession: Bool = false) {
        cancelSetupTimeout()
        stopHeartbeat()
        hasCompletedSetup = false
        setupCompleteTime = nil
        cancelAudioCaptureMonitor()
        resetPlayback()

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

    func cancelSetupTimeout() {
        setupTimeoutWorkItem?.cancel()
        setupTimeoutWorkItem = nil
    }

    func scheduleSetupTimeout(for socketTask: URLSessionWebSocketTask) {
        cancelSetupTimeout()

        let workItem = DispatchWorkItem { [weak self, weak socketTask] in
            guard let self, let socketTask else { return }
            guard self.socketTask === socketTask, !self.hasCompletedSetup else { return }

            self.setupTimeoutWorkItem = nil
            self.handleSocketTransportFailure(
                message: self.isResumingConnection
                    ? "Timed out while resuming Gemini Live session."
                    : "Timed out waiting for Gemini Live setup.",
                hadCompletedSetup: false
            )
        }

        setupTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.setupCompletionTimeout, execute: workItem)
    }

    func stopPreservedAudioSession() {
        cancelPendingReconnect()
        cancelSetupTimeout()
        stopHeartbeat()
        isResumingConnection = false
        onReconnectStateChange?(.none)
        onMicrophoneInputLevel?(0)
        onMicrophoneCaptureStateChange?(false)

        audioLifecycleQueue.async { [weak self] in
            self?.tearDownConnection(preserveAudioSession: false)
        }
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

        // Hosted Gemini Live uses short-lived auth_tokens. Let the view model request
        // a fresh token before reconnecting instead of reusing a possibly expired one.
        if shouldDelegateReconnectToViewModel(configuration: currentConfiguration) {
            return false
        }

        if requireSafeResumptionHandle && currentResumptionHandle == nil {
            return false
        }

        if currentResumptionHandle == nil && !allowFreshReconnectWithoutHandle {
            return false
        }

        let displayState: GeminiLiveConnectionState = preserveConnectedState ? .connected : .connecting
        let reconnectState: GeminiLiveReconnectState = requireSafeResumptionHandle ? .sessionRefresh : .transport
        // When the existing session is still alive (e.g. goAway with a resumption
        // handle while setup is complete), the user can keep talking until the
        // reconnect actually fires. Defer the "Refreshing..." UI emit to the
        // workItem so the notch banner doesn't show during the idle wait.
        let deferStateEmit = requireSafeResumptionHandle && preserveConnectedState
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReconnectWorkItem = nil
            guard !self.userInitiatedDisconnect else { return }

            if deferStateEmit {
                self.onReconnectStateChange?(reconnectState)
                self.onStateChange?(displayState, statusText)
            }

            self.startConnection(
                using: currentConfiguration,
                statusText: self.currentResumptionHandle != nil ? "Resuming Gemini Live..." : "Reconnecting to Gemini Live...",
                displayState: displayState,
                preserveAudioSession: preserveAudioSession
            )
        }

        pendingReconnectWorkItem = workItem
        if !deferStateEmit {
            onReconnectStateChange?(reconnectState)
            onStateChange?(displayState, statusText)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return true
    }

    private func nextReconnectDelay() -> TimeInterval {
        let exp = min(Self.maxReconnectDelay, Self.baseReconnectDelay * pow(2.0, Double(reconnectAttemptCount)))
        let jitter = exp < Self.maxReconnectDelay ? Double.random(in: 0..<(exp * 0.3)) : 0
        return min(Self.maxReconnectDelay, exp + jitter)
    }

    private func reconnectStatusText() -> String {
        currentResumptionHandle != nil ? "Resuming Gemini Live session..." : "Reconnecting to Gemini Live..."
    }

    func resetReconnectBackoff() {
        reconnectAttemptCount = 0
        hasLoggedUnstableConnection = false
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

    func beginHeartbeatAfterSetup() {
        resetReconnectBackoff()
        lastMessageReceivedAt = Date()
        startHeartbeat()
    }

    @discardableResult
    private func scheduleTransportReconnect(
        hadCompletedSetup: Bool,
        preserveAudioSession: Bool
    ) -> Bool {
        let delay = nextReconnectDelay()
        reconnectAttemptCount += 1

        if delay >= Self.maxReconnectDelay, reconnectAttemptCount >= 10, !hasLoggedUnstableConnection {
            hasLoggedUnstableConnection = true
            NotchLog.gemini.error(
                "Gemini Live connection unstable: reconnect backoff capped at \(Self.maxReconnectDelay, privacy: .public)s."
            )
        }

        return scheduleAutomaticReconnect(
            after: delay,
            statusText: reconnectStatusText(),
            preserveConnectedState: hadCompletedSetup,
            allowFreshReconnectWithoutHandle: !hadCompletedSetup,
            preserveAudioSession: preserveAudioSession
        )
    }

    private func handleSocketTransportFailure(message: String, hadCompletedSetup: Bool) {
        let shouldPreserveAudioSession = hadCompletedSetup && captureMode == .webRTC

        if !hadCompletedSetup && isResumingConnection {
            clearSessionResumptionHandle()
            isResumingConnection = false
        }

        tearDownConnection(preserveAudioSession: shouldPreserveAudioSession)
        if pendingReconnectWorkItem != nil {
            cancelPendingReconnect()
        }

        if scheduleTransportReconnect(
            hadCompletedSetup: hadCompletedSetup,
            preserveAudioSession: shouldPreserveAudioSession
        ) {
            return
        }

        handleFailure(message: message, preserveAudioSession: shouldPreserveAudioSession)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        guard hasCompletedSetup else { return }

        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.hasCompletedSetup, let socketTask = self.socketTask else { return }

            let now = Date()
            if let lastMessageReceivedAt = self.lastMessageReceivedAt,
               now.timeIntervalSince(lastMessageReceivedAt) > Self.heartbeatWatchdogInterval {
                NotchLog.gemini.debug(
                    "Gemini Live heartbeat detected a stale connection after \(Int(now.timeIntervalSince(lastMessageReceivedAt)), privacy: .public)s without inbound traffic."
                )
                self.handleSocketTransportFailure(
                    message: "Gemini Live connection became unresponsive.",
                    hadCompletedSetup: self.hasCompletedSetup
                )
                return
            }

            socketTask.sendPing { error in
                guard self.socketTask === socketTask else { return }

                if let error {
                    NotchLog.gemini.debug(
                        "Gemini Live heartbeat ping failed: \(error.localizedDescription, privacy: .public)"
                    )
                    self.handleSocketTransportFailure(
                        message: "Gemini Live heartbeat failed: \(error.localizedDescription)",
                        hadCompletedSetup: self.hasCompletedSetup
                    )
                    return
                }

                self.lastMessageReceivedAt = Date()
            }
        }

        pingTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        pingTimer?.cancel()
        pingTimer = nil
        lastMessageReceivedAt = nil
    }

    func parseGoAwayTimeLeft(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("s") else { return nil }
        return Double(trimmed.dropLast())
    }

    private func shouldDelegateReconnectToViewModel(configuration: LiveSessionConfiguration) -> Bool {
        configuration.backendConfiguration != nil && configuration.connectionCredential.hasPrefix("auth_tokens/")
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
                "slidingWindow": [
                    "targetTokens": Self.defaultContextWindowTargetTokens,
                ],
                "triggerTokens": Self.defaultContextWindowTriggerTokens,
            ] as [String: Any],
            "sessionResumption": currentResumptionHandle.map { ["handle": $0] } ?? [:],
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
        ]
        if !liveSetupTools.isEmpty {
            setup["tools"] = liveSetupTools
        }
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

        let message: String
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let encodedMessage = String(data: data, encoding: .utf8) else {
                handleFailure(
                    message: "Couldn't encode the Gemini Live message.",
                    preserveAudioSession: hasCompletedSetup && captureMode == .webRTC
                )
                onCompletion?(false)
                return
            }
            message = encodedMessage
        } catch {
            handleFailure(
                message: "Couldn't prepare the Gemini Live payload.",
                preserveAudioSession: hasCompletedSetup && captureMode == .webRTC
            )
            onCompletion?(false)
            return
        }

        sendQueue.async { [weak self] in
            guard let self else { return }

            socketTask.send(.string(message)) { error in
                guard self.socketTask === socketTask else {
                    onCompletion?(false)
                    return
                }

                if let error {
                    let hadCompletedSetup = self.hasCompletedSetup
                    self.handleSocketTransportFailure(
                        message: "Gemini Live send failed: \(error.localizedDescription)",
                        hadCompletedSetup: hadCompletedSetup
                    )
                    onCompletion?(false)
                } else {
                    onCompletion?(true)
                }
            }
        }
    }

    func receiveNextMessage() {
        guard let socketTask else { return }

        socketTask.receive { [weak self] result in
            guard let self else { return }
            guard self.socketTask === socketTask else {
                return
            }

            switch result {
            case let .failure(error):
                guard !self.userInitiatedDisconnect else { return }
                self.handleSocketTransportFailure(
                    message: "Gemini Live disconnected: \(error.localizedDescription)",
                    hadCompletedSetup: self.hasCompletedSetup
                )
            case let .success(message):
                self.handleMessage(message)
                self.receiveNextMessage()
            }
        }
    }

    func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        autoreleasepool {
            lastMessageReceivedAt = Date()
            let rawData: Data?

            switch message {
            case let .string(text):
                rawData = text.data(using: .utf8)
            case let .data(data):
                rawData = data
            @unknown default:
                NotchLog.gemini.debug("Gemini Live received an unknown WebSocket message type.")
                rawData = nil
            }

            guard
                let rawData,
                let object = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            else {
                let previewLimit = 200
                let previewData = rawData?.prefix(previewLimit) ?? Data()
                let preview = String(decoding: previewData, as: UTF8.self)
                NotchLog.gemini.debug(
                    "Gemini Live dropped an unparseable message: bytes=\(rawData?.count ?? 0, privacy: .public) preview=\(preview, privacy: .private(mask: .hash))"
                )
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

            if let usageMetadata = object["usageMetadata"] as? [String: Any] {
                onUsageMetadata?(GeminiLiveUsageMetadata(dictionary: usageMetadata))
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
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onModelThinkingStateChange?(true)
                }
            }

            if
                let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
                let text = outputTranscription["text"] as? String
            {
                onModelThinkingStateChange?(false)
                onModelTranscript?(text)
            }

            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                onModelThinkingStateChange?(false)
                onTurnComplete?()
            }

            if let generationComplete = serverContent["generationComplete"] as? Bool, generationComplete {
                // Docs: signals the model finished generating its response.
                // Audio playback may still be in progress at this point.
                onModelThinkingStateChange?(false)
            }

            if
                let modelTurn = serverContent["modelTurn"] as? [String: Any],
                let parts = modelTurn["parts"] as? [[String: Any]]
            {
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
        } // autoreleasepool
    }

}

struct LiveSessionConfiguration {
    let connectionCredential: String
    let restAPIKey: String?
    let backendConfiguration: GeminiLiveBackendConfiguration?
    let model: String
    let systemPrompt: String?
    let thinkingBudget: Int
    let voiceName: String
    let skillSnapshot: SkillSessionSnapshot?
}
