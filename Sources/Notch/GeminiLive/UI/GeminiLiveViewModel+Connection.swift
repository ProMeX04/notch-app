import Foundation
import NotchChatHistoryFeature
import NotchGeminiLiveCore

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
            if !clearingTranscripts, let existingConfiguration = self.session.currentConfiguration {
                if existingConfiguration.isManagedCredential,
                   self.shouldRefreshManagedServerCredential(existingConfiguration) {
                    guard let freshBackend = await self.backend.freshConfiguredPortalUserConfiguration() else {
                        self.setConnectionState(.failed)
                        self.lastErrorMessage = "Please sign in to your Gemini Live server account."
                        self.statusText = self.defaultDisconnectedStatusText
                        self.handleUnrecoverableReconnectFailureIfNeeded()
                        return
                    }

                    self.statusText = "Requesting secure Gemini Live token..."
                    do {
                        let token = try await self.requestManagedServerSessionToken(
                            configuration: freshBackend,
                            model: existingConfiguration.model,
                            systemInstruction: existingConfiguration.systemPrompt,
                            voiceName: existingConfiguration.voiceName,
                            thinkingConfiguration: existingConfiguration.thinkingConfiguration,
                            mediaResolution: existingConfiguration.mediaResolution
                        )
                        self.session.resume(using: existingConfiguration.replacingCredential(with: token))
                    } catch {
                        if self.backend.shouldClearBackendAuthSession(for: error) {
                            self.backend.clearBackendAuthSession()
                        }
                        self.logGeminiFailure("session token refresh failed", error: error)
                        self.setConnectionState(.failed)
                        self.lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        self.statusText = "Couldn't refresh the Gemini Live session token."
                        _ = self.scheduleReconnect()
                        return
                    }
                } else {
                    self.session.resume(using: existingConfiguration)
                }
                self.syncEffectiveMicrophoneState()
                return
            }

            let effectiveTools = self.effectiveEnabledTools
            let systemPrompt = self.buildSystemPrompt(
                effectiveTools: effectiveTools,
                userContent: self.userProfileContent,
                memoryContent: self.memoryContent
            )

            let preset = self.selectedSystemPromptPreset
            let systemInstruction = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let connectionCredential: String
            let restAPIKey: String?
            let backendConfiguration: PortalBackendConfiguration?
            var tokenResponse: GeminiLiveEphemeralTokenResponse?

            switch self.selectedConnectionMethod {
            case .managedServer:
                guard let configuredBackend = await self.backend.freshConfiguredPortalUserConfiguration() else {
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
                        thinkingConfiguration: preset.thinkingEnum.wireConfiguration(forModel: preset.modelAPIName),
                        mediaResolution: preset.mediaResolutionEnum
                    )
                    tokenResponse = token
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

            self.session.connect(
                connectionCredential: connectionCredential,
                restAPIKey: restAPIKey,
                backendConfiguration: backendConfiguration,
                model: preset.modelAPIName,
                systemPrompt: systemPrompt,
                microphoneEnabled: self.effectiveMicrophoneEnabled && self.hasMicrophonePermission,
                microphonePrewarmingEnabled: self.inputMode == .pushToTalk,
                credentialExpireTime: tokenResponse?.expireDate,
                thinkingConfiguration: preset.thinkingEnum.wireConfiguration(forModel: preset.modelAPIName),
                voiceName: preset.voiceEnum.apiName,
                mediaResolution: preset.mediaResolutionEnum,
                enabledTools: effectiveTools
            )
            self.syncEffectiveMicrophoneState()
        }
    }

    func requestManagedServerSessionToken(
        configuration: PortalBackendConfiguration,
        model: String,
        systemInstruction: String?,
        voiceName: String,
        thinkingConfiguration: GeminiThinkingWireConfiguration?,
        mediaResolution: GeminiMediaResolution
    ) async throws -> GeminiLiveEphemeralTokenResponse {
        let thinkingLevel: String?
        let thinkingBudget: Int?
        if let thinkingConfiguration {
            switch thinkingConfiguration {
            case let .level(level):
                thinkingLevel = level
                thinkingBudget = nil
            case let .budget(budget):
                thinkingLevel = nil
                thinkingBudget = budget
            case .automatic:
                thinkingLevel = nil
                thinkingBudget = nil
            }
        } else {
            thinkingLevel = nil
            thinkingBudget = nil
        }
        return try await backendClient.createGeminiLiveSessionToken(
            configuration: configuration,
            request: GeminiLiveSessionTokenRequest(
                model: model,
                systemInstruction: systemInstruction,
                voiceName: voiceName,
                thinkingLevel: thinkingLevel,
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
        toastClearTask = nil
        lastToolAction = nil
        isModelThinking = false
        isHoldToTalkActive = false
        isMicrophoneLive = false
        clearTranscripts()
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
        configuration.isManagedCredential
            && (session.currentResumptionHandle == nil || !configuration.canResumeConnection())
    }
}
