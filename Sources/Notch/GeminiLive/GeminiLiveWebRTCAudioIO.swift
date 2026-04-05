@preconcurrency import AVFoundation
import Foundation
import LiveKitWebRTC

final class GeminiLiveWebRTCAudioIO: NSObject, @unchecked Sendable {
    enum Error: LocalizedError {
        case playoutFailed(Int)
        case recordingFailed(Int)

        var errorDescription: String? {
            switch self {
            case let .playoutFailed(code):
                return "WebRTC playout failed with code \(code)."
            case let .recordingFailed(code):
                return "WebRTC recording failed with code \(code)."
            }
        }
    }

    private let queue = DispatchQueue(label: "dev.notch.gemini.webrtc")
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    private let peerConnectionFactory: LKRTCPeerConnectionFactory
    private let audioDeviceModule: LKRTCAudioDeviceModule
    private let audioProcessingModule: LKRTCDefaultAudioProcessingModule
    private let outputPlayer = AVAudioPlayerNode()
    private let observerProxy: ObserverProxy

    private var engine: AVAudioEngine?
    private var outputAttached = false
    private weak var tappedInputNode: AVAudioNode?
    private var inputTapInstalled = false
    private var playoutStarted = false
    private var recordingStarted = false
    private var onCapture: ((AVAudioPCMBuffer) -> Void)?

    var isCapturing: Bool { recordingStarted }

    override init() {
        let apmConfig = LKRTCAudioProcessingConfig()
        apmConfig.isEchoCancellationEnabled = true
        apmConfig.isEchoCancellationMobileMode = true
        apmConfig.isNoiseSuppressionEnabled = true
        apmConfig.isHighpassFilterEnabled = true
        apmConfig.isAutoGainControl1Enabled = true
        apmConfig.isAutoGainControl2Enabled = true

        let audioProcessingModule = LKRTCDefaultAudioProcessingModule(
            config: apmConfig,
            capturePostProcessingDelegate: nil,
            renderPreProcessingDelegate: nil
        )
        self.audioProcessingModule = audioProcessingModule

        let factory = LKRTCPeerConnectionFactory(
            audioDeviceModuleType: .audioEngine,
            bypassVoiceProcessing: false,
            encoderFactory: nil,
            decoderFactory: nil,
            audioProcessingModule: audioProcessingModule
        )
        peerConnectionFactory = factory
        audioDeviceModule = factory.audioDeviceModule
        _ = audioDeviceModule.setVoiceProcessingEnabled(true)
        audioDeviceModule.isVoiceProcessingBypassed = false
        audioDeviceModule.isVoiceProcessingAGCEnabled = true

        observerProxy = ObserverProxy()

        super.init()

        observerProxy.owner = self
        audioDeviceModule.observer = observerProxy
    }

    deinit {
        stop()
    }

    func startOutput() throws {
        try ensurePlayoutStarted()
    }

    func startCapture(onCapture: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.onCapture = onCapture
        try ensurePlayoutStarted()

        if recordingStarted {
            _ = audioDeviceModule.setMicrophoneMuted(false)
            return
        }

        let result = audioDeviceModule.initAndStartRecording()
        guard result == 0 else {
            throw Error.recordingFailed(result)
        }

        _ = audioDeviceModule.setMicrophoneMuted(false)
        recordingStarted = true
    }

    func setMicrophoneMuted(_ muted: Bool) {
        guard recordingStarted else { return }
        _ = audioDeviceModule.setMicrophoneMuted(muted)
    }

    func setOutputVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        queue.async { [weak self] in
            self?.outputPlayer.volume = clamped
        }
    }

    func stopCapture() {
        onCapture = nil

        guard recordingStarted else { return }
        _ = audioDeviceModule.stopRecording()
        recordingStarted = false
    }

    func enqueueOutputAudio(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let engine = self.engine, engine.isRunning else { return }

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

            self.outputPlayer.scheduleBuffer(buffer, completionHandler: nil)
            if !self.outputPlayer.isPlaying {
                self.outputPlayer.play()
            }
        }
    }

    func resetOutput() {
        queue.async { [weak self] in
            self?.outputPlayer.stop()
        }
    }

    func stop() {
        stopCapture()

        if playoutStarted {
            _ = audioDeviceModule.stopPlayout()
            playoutStarted = false
        }

        queue.sync {
            removeInputTapIfPossibleLocked()
            detachOutputPlayerLocked()
            self.engine = nil
        }
    }

    private func ensurePlayoutStarted() throws {
        guard !playoutStarted else { return }

        let initResult = audioDeviceModule.initPlayout()
        guard initResult == 0 else {
            throw Error.playoutFailed(initResult)
        }

        let startResult = audioDeviceModule.startPlayout()
        guard startResult == 0 else {
            throw Error.playoutFailed(startResult)
        }

        playoutStarted = true
    }

    private func attachOutputPlayerIfNeeded(to engine: AVAudioEngine) {
        queue.sync {
            self.engine = engine

            guard !outputAttached else { return }

            engine.attach(outputPlayer)
            engine.connect(outputPlayer, to: engine.mainMixerNode, format: outputFormat)
            outputAttached = true
        }
    }

    private func detachOutputPlayer(from engine: AVAudioEngine) {
        queue.sync {
            detachOutputPlayerLocked(from: engine)
        }
    }

    fileprivate func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        onCapture?(buffer)
    }

    fileprivate func handleDidCreateEngine(_ engine: AVAudioEngine) {
        attachOutputPlayerIfNeeded(to: engine)
    }

    fileprivate func handleConfigureInput(source: AVAudioNode?, destination: AVAudioNode, format: AVAudioFormat) {
        let tapNode = destination

        queue.sync {
            if inputTapInstalled, tappedInputNode !== tapNode {
                removeInputTapIfPossibleLocked()
            }

            guard !inputTapInstalled else { return }

            tapNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
                guard let self, let clone = self.clone(buffer) else { return }
                self.handleCapturedBuffer(clone)
            }
            tappedInputNode = tapNode
            inputTapInstalled = true
        }
    }

    fileprivate func handleWillReleaseEngine(_ engine: AVAudioEngine) {
        queue.sync {
            removeInputTapIfPossibleLocked(attachedTo: engine)
            detachOutputPlayerLocked(from: engine)
        }
    }

    private func removeInputTapIfPossibleLocked(attachedTo expectedEngine: AVAudioEngine? = nil) {
        guard inputTapInstalled else {
            tappedInputNode = nil
            return
        }

        guard let tappedInputNode else {
            inputTapInstalled = false
            return
        }

        guard let currentEngine = tappedInputNode.engine else {
            self.tappedInputNode = nil
            inputTapInstalled = false
            return
        }

        if let expectedEngine, currentEngine !== expectedEngine {
            return
        }

        tappedInputNode.removeTap(onBus: 0)
        self.tappedInputNode = nil
        inputTapInstalled = false
    }

    private func detachOutputPlayerLocked(from expectedEngine: AVAudioEngine? = nil) {
        outputPlayer.stop()

        guard outputAttached else {
            if let expectedEngine, engine === expectedEngine {
                engine = nil
            }
            return
        }

        if let currentEngine = engine, expectedEngine == nil || currentEngine === expectedEngine {
            currentEngine.detach(outputPlayer)
        }

        outputAttached = false

        if let expectedEngine, engine === expectedEngine {
            engine = nil
        }
    }

    private func clone(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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

private final class ObserverProxy: NSObject, LKRTCAudioDeviceModuleDelegate {
    weak var owner: GeminiLiveWebRTCAudioIO?

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, didReceiveSpeechActivityEvent speechActivityEvent: LKRTCSpeechActivityEvent) {}

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, didCreateEngine engine: AVAudioEngine) -> Int {
        owner?.handleDidCreateEngine(engine)
        return 0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, willEnableEngine engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, willStartEngine engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, didStopEngine engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, didDisableEngine engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, willReleaseEngine engine: AVAudioEngine) -> Int {
        owner?.handleWillReleaseEngine(engine)
        return 0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, engine: AVAudioEngine, configureInputFromSource src: AVAudioNode?, toDestination dst: AVAudioNode, format: AVAudioFormat, context: [AnyHashable: Any]) -> Int {
        owner?.handleConfigureInput(source: src, destination: dst, format: format)
        return 0
    }

    func audioDeviceModule(_ audioDeviceModule: LKRTCAudioDeviceModule, engine: AVAudioEngine, configureOutputFromSource src: AVAudioNode, toDestination dst: AVAudioNode?, format: AVAudioFormat, context: [AnyHashable: Any]) -> Int {
        0
    }

    func audioDeviceModuleDidUpdateDevices(_ audioDeviceModule: LKRTCAudioDeviceModule) {}
}
