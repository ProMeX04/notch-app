@preconcurrency import AVFoundation
import Foundation
import NotchChatHistoryFeature

extension GeminiLiveViewModel {
    func startFullScreenSharing() {
        cameraShare.stop()
        screenShare.setMediaResolution(activeVisualMediaResolution)
        screenShare.startFullScreen()
    }

    func startRegionScreenSharing() {
        cameraShare.stop()
        screenShare.setMediaResolution(activeVisualMediaResolution)
        screenShare.startRegion()
    }

    func startWindowSharing() {
        cameraShare.stop()
        screenShare.setMediaResolution(activeVisualMediaResolution)
        screenShare.startWindow()
    }

    func startCameraSharing() {
        screenShare.stop()
        cameraShare.setMediaResolution(activeVisualMediaResolution)
        cameraShare.start()
    }

    private var activeVisualMediaResolution: GeminiMediaResolution {
        session.currentConfiguration?.mediaResolution ?? mediaResolution
    }

    func stopVisualSharing() {
        screenShare.stop()
        cameraShare.stop()
    }

    func stopScreenSharing() {
        stopVisualSharing()
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

    var hasMicrophonePermission: Bool {
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

    @discardableResult
    func sendLiveChatMessage(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard canSendLiveInput else { return false }

        let hadPendingModelTurn = !modelTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        commitModelTurnIfPending()
        commitUserVoiceTurnIfPending()
        suppressModelTranscriptUntilTurnComplete = hadPendingModelTurn

        session.sendClientTextTurn(trimmed)
        userTurnSequence += 1

        let msg = LiveChatMessage(id: UUID(), isUser: true, text: trimmed)
        liveChatMessages.append(msg)

        userTranscript = ""
        isModelThinking = true
        TranscriptSessionLogger.shared.recordUserText(trimmed)
        GeminiLiveChatHistoryStore.shared.save(trimmed)
        return true
    }

    func clearTranscripts() {
        userTranscript = ""
        modelTranscript = ""
        liveChatMessages = []
        currentTurnAudioData = Data()
        currentUserTurnAudioData = Data()
        pendingTurnSeparator = false
        suppressModelTranscriptUntilTurnComplete = false
        isModelThinking = false
        isModelSpeaking = false
        lastErrorMessage = nil
    }

    func syncEffectiveMicrophoneState() {
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
}
