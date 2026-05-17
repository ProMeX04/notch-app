@preconcurrency import AVFoundation
import CoreImage
import Foundation

@MainActor
final class CameraShareCoordinator: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?

    private let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "dev.notch.gemini.camera-share")
    private var activeInput: AVCaptureDeviceInput?
    private var activeOutput: AVCaptureVideoDataOutput?
    private nonisolated(unsafe) var nextFrameSendTime: CFTimeInterval = 0
    private nonisolated let sendFrameInterval: CFTimeInterval = 1.5

    var onFrameCaptured: (@MainActor (Data) -> Void)?
    var onStatusChange: (@MainActor (String?) -> Void)?
    var onErrorMessageChange: (@MainActor (String?) -> Void)?
    var connectionStateProvider: (@MainActor () -> GeminiLiveConnectionState)?

    func start() {
        ensurePermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.onErrorMessageChange?("Camera permission is required to share your camera.")
                self.setStatusMessage("Allow Camera access for Notch, then try again.")
                return
            }
            self.startCapture()
        }
    }

    func stop() {
        stopCapture()
        if isConnectedOrConnecting {
            setStatusMessage("Camera sharing stopped.")
        }
    }

    func shutdown() {
        stopCapture()
    }

    private var isConnectedOrConnecting: Bool {
        guard let connectionStateProvider else { return false }
        let state = connectionStateProvider()
        return state == .connected || state == .connecting
    }

    private func ensurePermission(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in completion(granted) }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func startCapture() {
        stopCapture()

        guard let device = AVCaptureDevice.default(for: .video) else {
            onErrorMessageChange?("No camera is available.")
            setStatusMessage("No camera is available.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: captureQueue)

            activeInput = input
            activeOutput = output
            nextFrameSendTime = 0
            setStatusMessage("Starting camera sharing...")

            let session = captureSession
            captureQueue.async { [weak self, input, output, session] in
                session.beginConfiguration()
                session.sessionPreset = .medium

                for existingInput in session.inputs {
                    session.removeInput(existingInput)
                }
                for existingOutput in session.outputs {
                    if let videoOutput = existingOutput as? AVCaptureVideoDataOutput {
                        videoOutput.setSampleBufferDelegate(nil, queue: nil)
                    }
                    session.removeOutput(existingOutput)
                }

                let canAddInput = session.canAddInput(input)
                let canAddOutput = session.canAddOutput(output)
                guard canAddInput, canAddOutput else {
                    session.commitConfiguration()
                    Task { @MainActor [weak self] in
                        self?.activeInput = nil
                        self?.activeOutput = nil
                        self?.onErrorMessageChange?("Unable to start camera sharing.")
                        self?.setStatusMessage("Unable to start camera sharing.")
                    }
                    return
                }

                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                let didStart = session.isRunning

                Task { @MainActor [weak self] in
                    guard let self, self.activeInput === input, self.activeOutput === output else { return }
                    if didStart {
                        self.isActive = true
                        self.setStatusMessage("Sharing camera.")
                    } else {
                        self.activeInput = nil
                        self.activeOutput = nil
                        self.onErrorMessageChange?("Unable to start camera sharing.")
                        self.setStatusMessage("Unable to start camera sharing. Camera session did not start.")
                    }
                }
            }
        } catch {
            activeInput = nil
            activeOutput = nil
            onErrorMessageChange?("Unable to start camera: \(error.localizedDescription)")
            setStatusMessage("Unable to start camera sharing: \(error.localizedDescription)")
        }
    }

    private func stopCapture() {
        let wasActive = isActive || activeInput != nil || activeOutput != nil
        guard wasActive || captureSession.isRunning else { return }
        isActive = false
        activeInput = nil
        activeOutput = nil
        let session = captureSession
        captureQueue.async {
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                if let videoOutput = output as? AVCaptureVideoDataOutput {
                    videoOutput.setSampleBufferDelegate(nil, queue: nil)
                }
                session.removeOutput(output)
            }
            session.commitConfiguration()
        }
    }

    private func setStatusMessage(_ message: String?) {
        statusMessage = message
        onStatusChange?(message)
    }

    private nonisolated static let jpegContext = CIContext(options: [.useSoftwareRenderer: false])

    private nonisolated static func encodeJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        let maxWidth: CGFloat = 1280
        let originalWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scale = min(1.0, maxWidth / originalWidth)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return jpegContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
        )
    }
}

extension CameraShareCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp >= nextFrameSendTime else { return }
        nextFrameSendTime = timestamp + sendFrameInterval

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = CameraShareCoordinator.encodeJPEG(from: pixelBuffer)
        else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isActive else { return }
            self.onFrameCaptured?(jpeg)
        }
    }
}
