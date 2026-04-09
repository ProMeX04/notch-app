@preconcurrency import AVFoundation
import Foundation

extension GeminiLiveSession {
    func prepareOutputIfNeeded() {
        guard !outputPrepared else { return }

        if captureMode == .webRTC {
            let audioIO = webRTCAudioIO ?? GeminiLiveWebRTCAudioIO()
            webRTCAudioIO = audioIO

            do {
                try audioIO.startOutput()
                audioIO.setOutputVolume(outputVolume)
                outputPrepared = true

                // Start capture early so WebRTC AEC can calibrate the echo path
                // before the first user turn. processCapturedBuffer already guards
                // with `hasCompletedSetup`, so no audio will be sent prematurely.
                if microphoneEnabled {
                    try audioIO.startCapture { [weak self] buffer in
                        guard let self else { return }
                        // Buffer is already cloned by GeminiLiveWebRTCAudioIO — no second clone needed.
                        self.audioProcessingQueue.async { [weak self] in
                            guard let self else { return }
                            if self.inputConverter == nil {
                                self.inputConverter = AVAudioConverter(from: buffer.format, to: self.inputTargetFormat)
                            }
                            self.processCapturedBuffer(buffer)
                        }
                    }
                }
            } catch {
                handleFailure(message: error.localizedDescription)
            }
            return
        }

        outputEngine.attach(outputPlayer)
        outputEngine.connect(outputPlayer, to: outputEngine.mainMixerNode, format: outputFormat)
        outputPlayer.volume = outputVolume
        outputPrepared = true
    }

    func enqueueOutputAudio(_ data: Data) {
        guard allowModelAudioPlayback else { return }

        if captureMode == .webRTC {
            webRTCAudioIO?.enqueueOutputAudio(data)
            return
        }

        playbackQueue.async { [weak self] in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
            guard frameCount > 0 else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: self.outputFormat, frameCapacity: frameCount) else {
                return
            }

            buffer.frameLength = frameCount

            let audioBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard let audioBuffer = audioBufferList.first, let destination = audioBuffer.mData else {
                return
            }

            data.withUnsafeBytes { source in
                guard let sourceAddress = source.baseAddress else { return }
                memcpy(destination, sourceAddress, data.count)
            }

            if !self.outputEngine.isRunning {
                try? self.outputEngine.start()
            }

            if !self.outputPlayer.isPlaying {
                self.outputPlayer.play()
            }
            self.outputPlayer.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    func resetPlayback() {
        if captureMode == .webRTC {
            webRTCAudioIO?.resetOutput()
            return
        }

        playbackQueue.async { [weak self] in
            guard let self else { return }
            self.outputPlayer.stop()
        }
    }

    func startMicrophone() {
        guard microphoneEnabled else { return }
        guard setupCompleteTime != nil else { return }
        prepareOutputIfNeeded()
        audioChunkCount = 0

        switch captureMode {
        case .webRTC:
            startWebRTCMicrophone()
        case .voiceProcessing:
            startVoiceProcessedMicrophone()
        case .standard:
            startStandardMicrophone()
        }
    }

    func stopMicrophone(notifyModel: Bool) {
        onMicrophoneInputLevel?(0)

        if captureMode == .webRTC {
            webRTCAudioIO?.stopCapture()
        }

        if outputPrepared, captureMode == .voiceProcessing {
            outputEngine.inputNode.isVoiceProcessingInputMuted = true
        }

        if let standardInputEngine, standardInputEngine.isRunning {
            standardInputEngine.stop()
        }

        if captureMode != .webRTC {
            teardownMicrophoneCapture()
        }

        if notifyModel {
            sendJSONObject([
                "realtimeInput": [
                    "audioStreamEnd": true,
                ],
            ])
        }
    }

    func processCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard microphoneEnabled else { return }
        guard socketTask != nil else { return }
        guard let setupTime = setupCompleteTime, Date().timeIntervalSince(setupTime) > 0.5 else { return }
        
        // Mute mic strictly during the model's VERY FIRST playback turn.
        // This gives Apple's Voice Processing I/O hardware time to converge and calibrate its Echo Cancellation path.
        if isFirstModelTurn && modelHasSpoken {
            return
        }
        
        guard let converter = inputConverter else { return }

        let ratio = inputTargetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: inputTargetFormat, frameCapacity: outputCapacity) else {
            return
        }

        var error: NSError?
        var hasProvidedInput = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outputStatus in
            if hasProvidedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }

            hasProvidedInput = true
            outputStatus.pointee = .haveData
            return buffer
        }

        if let error {
            handleFailure(message: "Gemini Live audio conversion failed: \(error.localizedDescription)")
            return
        }

        guard status == .haveData || status == .inputRanDry else { return }
        guard outputBuffer.frameLength > 0 else { return }
        guard let channelData = outputBuffer.int16ChannelData?.pointee else { return }

        publishMicrophoneInputLevel(from: channelData, frameCount: Int(outputBuffer.frameLength))

        let pcmData = Data(
            bytes: channelData,
            count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        )

        guard !pcmData.isEmpty else { return }
        audioChunkCount += 1

        sendJSONObject([
            "realtimeInput": [
                "audio": [
                    "data": pcmData.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000",
                ],
            ],
        ])
    }

    func handleSessionResumptionUpdate(_ update: [String: Any]) {
        let resumable = update["resumable"] as? Bool ?? false
        latestSessionHandleIsResumable = resumable

        // Docs: only retain the handle when both resumable AND newHandle are present.
        if resumable, let newHandle = update["newHandle"] as? String, !newHandle.isEmpty {
            latestSessionHandle = newHandle
        }
    }

    func handleGoAway(_ goAway: [String: Any]) {
        guard latestSessionHandle != nil else { return }
        guard let timeLeft = parseGoAwayTimeLeft(goAway["timeLeft"] as? String) else { return }

        _ = scheduleAutomaticReconnect(
            after: max(0.1, timeLeft - 1.0),
            statusText: "Refreshing Gemini Live session...",
            requireSafeResumptionHandle: true,
            preserveConnectedState: hasCompletedSetup,
            preserveAudioSession: hasCompletedSetup && captureMode == .webRTC
        )
    }

    func handleFailure(message: String, preserveAudioSession: Bool = false) {
        cancelPendingReconnect()
        tearDownConnection(preserveAudioSession: preserveAudioSession)
        isResumingConnection = false
        onStateChange?(.failed, message)
    }

    func teardownMicrophoneCapture() {
        onMicrophoneInputLevel?(0)

        if microphoneTapInstalled {
            if captureMode == .voiceProcessing {
                outputEngine.inputNode.removeTap(onBus: 0)
            } else if captureMode == .standard {
                standardInputEngine?.inputNode.removeTap(onBus: 0)
            }
            microphoneTapInstalled = false
        }
        standardInputEngine = nil
        inputConverter = nil
    }

    private func publishMicrophoneInputLevel(from channelData: UnsafeMutablePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else {
            onMicrophoneInputLevel?(0)
            return
        }

        var sumSquares = 0.0
        for index in 0..<frameCount {
            let sample = Double(channelData[index]) / Double(Int16.max)
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        let normalized = min(max(pow(rms * 4.2, 0.6), 0), 1)
        onMicrophoneInputLevel?(normalized)
    }

    func handleSetupComplete() {
        guard socketTask != nil else { return }
        guard setupCompleteTime == nil else { return }

        hasCompletedSetup = true
        setupCompleteTime = Date()
        let statusMessage = isResumingConnection ? "Gemini Live resumed." : "Gemini Live is ready."
        isResumingConnection = false
        onStateChange?(.connected, statusMessage)

        if microphoneEnabled {
            startMicrophone()
        }
    }

    func configureVoiceProcessingIfNeeded() -> Bool {
        do {
            if !outputEngine.inputNode.isVoiceProcessingEnabled {
                try outputEngine.inputNode.setVoiceProcessingEnabled(true)
            }
            outputEngine.inputNode.isVoiceProcessingBypassed = false
            outputEngine.inputNode.isVoiceProcessingAGCEnabled = true
            return true
        } catch {
            return false
        }
    }

    func startVoiceProcessedMicrophone() {
        guard configureVoiceProcessingIfNeeded() else {
            captureMode = .standard
            onStateChange?(.connected, "Voice processing wasn't available. Using standard microphone mode.")
            startStandardMicrophone()
            return
        }

        let inputNode = outputEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        inputConverter = AVAudioConverter(from: inputFormat, to: inputTargetFormat)
        guard inputConverter != nil else {
            handleFailure(message: "Couldn't create the Gemini Live audio converter.")
            return
        }

        if !microphoneTapInstalled {
            inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] buffer, _ in
                guard let self, let clonedBuffer = GeminiPCMBufferCloner.clone(buffer) else { return }

                self.audioProcessingQueue.async { [weak self] in
                    self?.processCapturedBuffer(clonedBuffer)
                }
            }
            microphoneTapInstalled = true
        }

        inputNode.isVoiceProcessingInputMuted = false
        outputEngine.prepare()

        do {
            if !outputEngine.isRunning {
                try outputEngine.start()
            }
        } catch {
            handleFailure(message: "Couldn't start microphone capture: \(error.localizedDescription)")
            return
        }

        scheduleVoiceProcessingFallbackProbe()
    }

    func startWebRTCMicrophone() {
        let audioIO = webRTCAudioIO ?? GeminiLiveWebRTCAudioIO()
        webRTCAudioIO = audioIO

        // Capture may already be running (started early in prepareOutputIfNeeded
        // for AEC warm-up). In that case, skip — audio is already flowing.
        guard !audioIO.isCapturing else { return }

        do {
            try audioIO.startCapture { [weak self] buffer in
                guard let self else { return }
                // Buffer is already cloned by GeminiLiveWebRTCAudioIO — no second clone needed.
                self.audioProcessingQueue.async { [weak self] in
                    guard let self else { return }
                    if self.inputConverter == nil {
                        self.inputConverter = AVAudioConverter(from: buffer.format, to: self.inputTargetFormat)
                    }
                    self.processCapturedBuffer(buffer)
                }
            }
        } catch {
            captureMode = .standard
            onStateChange?(.connected, "WebRTC audio failed. Using standard microphone mode.")
            startStandardMicrophone()
        }
    }

    func startStandardMicrophone() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        inputConverter = AVAudioConverter(from: inputFormat, to: inputTargetFormat)
        guard inputConverter != nil else {
            handleFailure(message: "Couldn't create the Gemini Live audio converter.")
            return
        }

        if !microphoneTapInstalled {
            inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] buffer, _ in
                guard let self, let clonedBuffer = GeminiPCMBufferCloner.clone(buffer) else { return }

                self.audioProcessingQueue.async { [weak self] in
                    self?.processCapturedBuffer(clonedBuffer)
                }
            }
            microphoneTapInstalled = true
        }

        standardInputEngine = engine
        engine.prepare()

        do {
            try engine.start()
        } catch {
            handleFailure(message: "Couldn't start standard microphone capture: \(error.localizedDescription)")
        }
    }

    func scheduleVoiceProcessingFallbackProbe() {
        cancelAudioCaptureMonitor()

        let initialChunkCount = audioChunkCount
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.captureMode == .voiceProcessing else { return }
            guard self.microphoneEnabled, self.socketTask != nil else { return }
            guard self.audioChunkCount == initialChunkCount else { return }

            self.stopMicrophone(notifyModel: false)
            self.teardownMicrophoneCapture()
            self.captureMode = .standard
            self.onStateChange?(.connected, "Voice processing capture was quiet. Switched to standard microphone mode.")
            self.startMicrophone()
        }

        audioCaptureMonitorWorkItem = workItem
        sendQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func cancelAudioCaptureMonitor() {
        audioCaptureMonitorWorkItem?.cancel()
        audioCaptureMonitorWorkItem = nil
    }
}

private enum GeminiPCMBufferCloner {
    static func clone(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let clone = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        clone.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let source = buffer.floatChannelData, let destination = clone.floatChannelData else { return nil }
            let byteCount = frameCount * MemoryLayout<Float>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        case .pcmFormatInt16:
            guard let source = buffer.int16ChannelData, let destination = clone.int16ChannelData else { return nil }
            let byteCount = frameCount * MemoryLayout<Int16>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        case .pcmFormatInt32:
            guard let source = buffer.int32ChannelData, let destination = clone.int32ChannelData else { return nil }
            let byteCount = frameCount * MemoryLayout<Int32>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
        default:
            return nil
        }

        return clone
    }
}
