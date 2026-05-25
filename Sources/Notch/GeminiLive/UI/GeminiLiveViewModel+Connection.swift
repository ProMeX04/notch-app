import Foundation
import NotchChatHistoryCore

@MainActor
extension GeminiLiveViewModel {
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

    func connect(clearingTranscripts: Bool = true, preservingReconnectState: Bool = false) {
        if !preservingReconnectState && reconnectState != .fullRestart {
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
        setConnectionState(preservingReconnectState ? .connected : .connecting)
        if !shouldPreserveMicrophoneLiveStateDuringReconnect {
            isMicrophoneLive = false
            microphoneInputLevel = 0
        }
        lastErrorMessage = nil
        statusText = preservingReconnectState ? "Refreshing Gemini Live session..." : "Connecting to Gemini Live..."
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
                            model: preset.modelAPIName,
                            systemInstruction: systemInstruction.isEmpty ? nil : systemInstruction,
                            voiceName: preset.voiceEnum.apiName,
                            thinkingBudget: preset.thinkingEnum.budget > 0 ? preset.thinkingEnum.budget : nil,
                            mediaResolution: preset.mediaResolutionEnum
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
                        if self.reconnectState == .fullRestart || self.reconnectState == .sessionRefresh {
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
                model: preset.modelAPIName,
                systemPrompt: systemPrompt,
                microphoneEnabled: self.effectiveMicrophoneEnabled && self.hasMicrophonePermission,
                microphonePrewarmingEnabled: self.inputMode == .pushToTalk,
                thinkingBudget: preset.thinkingEnum.budget,
                voiceName: preset.voiceEnum.apiName,
                mediaResolution: preset.mediaResolutionEnum,
                enabledTools: skillSnapshot.effectiveTools,
                skillSnapshot: skillSnapshot,
                resumeSession: !clearingTranscripts
            )
            self.syncEffectiveMicrophoneState()
        }
    }

    func requestManagedServerSessionToken(
        configuration: GeminiLiveBackendConfiguration,
        model: String,
        systemInstruction: String?,
        voiceName: String,
        thinkingBudget: Int?,
        mediaResolution: GeminiMediaResolution
    ) async throws -> GeminiLiveEphemeralTokenResponse {
        try await backendClient.createSessionToken(
            configuration: configuration,
            requestBody: GeminiLiveSessionTokenRequest(
                model: model,
                systemInstruction: systemInstruction,
                voiceName: voiceName,
                thinkingBudget: thinkingBudget,
                mediaResolution: mediaResolution.apiName,
                responseModalities: ["AUDIO"]
            )
        )
    }

    func disconnect() {
        lastDisconnectWasUserInitiated = true
        cancelReconnect()
        stopVisualSharing()
        execApprovals.clearAll()
        toastClearTask = nil
        lastToolAction = nil
        isModelThinking = false
        isHoldToTalkActive = false
        isMicrophoneLive = false
        clearTranscripts()
        currentSkillSnapshot = nil
        session.disconnect(userInitiated: true)
        setConnectionState(.disconnected)
        statusText = defaultDisconnectedStatusText
        TranscriptSessionLogger.shared.endSession()
    }

    @discardableResult
    func scheduleReconnect() -> Bool {
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

    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        setReconnectState(.none)
    }

    func setConnectionState(_ state: GeminiLiveConnectionState) {
        connectionState = state
        recomputeLifecycleState()
    }

    func setReconnectState(_ state: GeminiLiveReconnectState) {
        reconnectState = state
        isAutoReconnecting = state != .none
        recomputeLifecycleState()
    }

    func recomputeLifecycleState() {
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

    func handleUnrecoverableReconnectFailureIfNeeded() {
        guard reconnectState == .fullRestart else { return }
        handleUnrecoverableReconnectFailure(statusText: statusText)
    }

    func handleUnrecoverableReconnectFailure(statusText: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        setReconnectState(.none)
        setConnectionState(.failed)
        self.statusText = statusText
        isHoldToTalkActive = false
        isModelThinking = false
        session.stopPreservedAudioSession()
        isMicrophoneLive = false
        microphoneInputLevel = 0
    }

    func logConnectAttempt(clearingTranscripts: Bool) {
        NotchLog.gemini.notice(
            "Connect requested: method=\(self.selectedConnectionMethod.rawValue, privacy: .public) auth=\(self.isBackendAuthenticated, privacy: .public) pro=\(self.isProUser, privacy: .public) clearingTranscripts=\(clearingTranscripts, privacy: .public)"
        )
    }

    func logConnectBlocked(reason: String) {
        NotchLog.gemini.notice(
            "Connect blocked: reason=\(reason, privacy: .public) method=\(self.selectedConnectionMethod.rawValue, privacy: .public) auth=\(self.isBackendAuthenticated, privacy: .public) pro=\(self.isProUser, privacy: .public)"
        )
    }

    func logGeminiFailure(_ summary: String, error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        NotchLog.gemini.error("\(summary, privacy: .public): \(message, privacy: .public)")
    }

    func shouldRefreshManagedServerCredential(_ configuration: LiveSessionConfiguration) -> Bool {
        configuration.backendConfiguration != nil && configuration.connectionCredential.hasPrefix("auth_tokens/")
    }
}
