import AppKit
import Combine
import CoreMedia
import Foundation
import NotchScreenShareCore
@preconcurrency import ScreenCaptureKit

enum ScreenShareMode {
    case fullScreen
    case selectedRegion
    case appWindow
}

private enum ScreenShareStreamError: LocalizedError {
    case invalidContentRect
    case missingContentFilter
    case missingDisplay

    var errorDescription: String? {
        switch self {
        case .invalidContentRect:
            return "The selected screen area cannot be shared."
        case .missingContentFilter:
            return "No app or window was selected to share."
        case .missingDisplay:
            return "The selected display is no longer available."
        }
    }
}

@MainActor
final class ScreenShareCoordinator: ObservableObject {
    @Published private(set) var mode: ScreenShareMode = .fullScreen
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var highlightRect: CGRect?
    @Published private(set) var selectedRegion: CGRect?

    private let regionSelectionController = ScreenRegionSelectionController()
    private let windowSelectionController = WindowShareSelectionController()
    private let highlightController = ScreenShareHighlightController()
    private let streamQueue = DispatchQueue(label: "dev.notch.gemini.screen-share")
    private var stream: SCStream?
    private var streamOutput: ScreenShareStreamOutput?
    private var streamDelegate: ScreenShareStreamDelegate?
    private var streamStartTask: Task<Void, Never>?
    private var contentFilter: SCContentFilter?
    private let sendFrameInterval: TimeInterval = 1.0
    private var visualProfile = ScreenShareVisualProfile.profile(source: .screen, resolution: .low)

    var onFrameCaptured: (@MainActor (Data) -> Void)?
    var onStatusChange: (@MainActor (String?) -> Void)?
    var onErrorMessageChange: (@MainActor (String?) -> Void)?
    var connectionStateProvider: (@MainActor () -> GeminiLiveConnectionState)?

    init() {
        highlightController.onRectChanged = { [weak self] rect in
            guard let self, self.isActive, self.mode == .selectedRegion else { return }
            let movedRegion = rect.integral
            self.selectedRegion = movedRegion
            self.highlightRect = movedRegion
        }
    }

    func setMediaResolution(_ resolution: GeminiMediaResolution) {
        visualProfile = .profile(source: .screen, resolution: resolution.screenShareMediaResolution)
    }

    func startFullScreen() {
        guard ensurePermission() else { return }
        regionSelectionController.cancelSelection(notify: false)
        windowSelectionController.cancelSelection(notify: false)
        mode = .fullScreen
        selectedRegion = nil
        contentFilter = nil
        updateHighlight()
        beginCapture(statusMessage: "Sharing full screen.")
    }

    func startRegion() {
        guard ensurePermission() else { return }
        let wasSharing = isActive
        let previousMode = mode
        let previousRegion = selectedRegion
        let previousFilter = contentFilter

        pauseCapture()
        updateHighlight()
        setStatusMessage("Drag to select a screen region. You can move the blue border while sharing. Press Esc to cancel.")

        regionSelectionController.beginSelection { [weak self] rect in
            guard let self else { return }

            guard let rect, rect.width >= 12, rect.height >= 12 else {
                if wasSharing {
                    self.mode = previousMode
                    self.selectedRegion = previousRegion
                    self.contentFilter = previousFilter
                    self.beginCapture(statusMessage: self.statusMessage(for: previousMode, selectedFilter: previousFilter))
                } else if self.isConnectedOrConnecting {
                    self.setStatusMessage("Region selection cancelled.")
                }
                return
            }

            self.mode = .selectedRegion
            self.selectedRegion = rect.integral
            self.contentFilter = nil
            self.updateHighlight()
            self.beginCapture(statusMessage: "Sharing selected region.")
        }
    }

    func startWindow() {
        guard ensurePermission() else { return }
        let wasSharing = isActive
        let previousMode = mode
        let previousRegion = selectedRegion
        let previousFilter = contentFilter

        pauseCapture()
        updateHighlight()
        setStatusMessage("Choose an app or window to share.")

        windowSelectionController.beginSelection { [weak self] selectedFilter in
            guard let self else { return }

            guard let selectedFilter else {
                if wasSharing {
                    self.mode = previousMode
                    self.selectedRegion = previousRegion
                    self.contentFilter = previousFilter
                    self.beginCapture(statusMessage: self.statusMessage(for: previousMode, selectedFilter: previousFilter))
                } else if self.isConnectedOrConnecting {
                    self.setStatusMessage("App or window selection cancelled.")
                }
                return
            }

            self.mode = .appWindow
            self.selectedRegion = nil
            self.contentFilter = selectedFilter
            self.updateHighlight()
            self.beginCapture(statusMessage: self.statusMessage(for: .appWindow, selectedFilter: selectedFilter))
        }
    }

    func stop() {
        stopCapture()
        if isConnectedOrConnecting {
            setStatusMessage("Screen sharing stopped.")
        }
    }

    func pauseCapture() {
        streamStartTask?.cancel()
        streamStartTask = nil
        let activeStream = stream
        stream = nil
        streamOutput = nil
        streamDelegate = nil
        isActive = false

        if let activeStream {
            Task.detached(priority: .userInitiated) {
                try? await activeStream.stopCapture()
            }
        }
    }

    func resumeCapture() {
        beginCapture(statusMessage: statusMessage(for: mode, selectedFilter: contentFilter))
    }

    func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        if granted {
            return true
        }

        onErrorMessageChange?("Screen Recording permission is required to share your screen.")
        setStatusMessage("Allow Screen Recording for Notch, then try again.")
        return false
    }

    func shutdown() {
        stopCapture()
    }

    private var isConnectedOrConnecting: Bool {
        guard let connectionStateProvider else { return false }
        let state = connectionStateProvider()
        return state == .connected || state == .connecting
    }

    private func beginCapture(statusMessage: String) {
        pauseCapture()
        isActive = true
        setStatusMessage(statusMessage)
        updateHighlight()

        let mode = mode
        let region = selectedRegion
        let selectedFilter = contentFilter
        let visualProfile = visualProfile
        streamStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let streamComponents = try await self.makeStreamComponents(
                    mode: mode,
                    region: region,
                    contentFilter: selectedFilter,
                    visualProfile: visualProfile
                )
                guard !Task.isCancelled, self.isActive else { return }

                let output = ScreenShareStreamOutput(
                    sendFrameInterval: self.sendFrameInterval,
                    maximumLongEdge: visualProfile.maximumLongEdge
                ) { [weak self] data in
                    guard let self, self.isActive else { return }
                    self.onFrameCaptured?(data)
                }
                try streamComponents.stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.streamQueue)
                self.stream = streamComponents.stream
                self.streamOutput = output
                self.streamDelegate = streamComponents.delegate
                try await streamComponents.stream.startCapture()
            } catch {
                guard !Task.isCancelled else { return }
                NotchLog.gemini.debug("Screen stream failed: \(error.localizedDescription, privacy: .public)")
                self.stream = nil
                self.streamOutput = nil
                self.streamDelegate = nil
                self.isActive = false
                self.updateHighlight()
                self.onErrorMessageChange?("Unable to start screen sharing: \(error.localizedDescription)")
                self.setStatusMessage("Unable to start screen sharing.")
            }
        }
    }

    private func stopCapture() {
        regionSelectionController.cancelSelection(notify: false)
        windowSelectionController.cancelSelection(notify: false)
        pauseCapture()
        updateHighlight()
    }

    private func updateHighlight() {
        guard isActive else {
            highlightRect = nil
            highlightController.hide()
            return
        }

        switch mode {
        case .fullScreen:
            highlightRect = nil
            highlightController.hide()
        case .selectedRegion:
            guard let selectedRegion else {
                highlightRect = nil
                highlightController.hide()
                return
            }
            highlightRect = selectedRegion
            highlightController.show(rect: selectedRegion)
        case .appWindow:
            highlightRect = nil
            highlightController.hide()
        }
    }

    private struct ScreenShareStreamComponents {
        let stream: SCStream
        let delegate: ScreenShareStreamDelegate
    }

    private func makeStreamComponents(
        mode: ScreenShareMode,
        region: CGRect?,
        contentFilter: SCContentFilter?,
        visualProfile: ScreenShareVisualProfile
    ) async throws -> ScreenShareStreamComponents {
        switch mode {
        case .fullScreen, .selectedRegion:
            return try await makeDisplayStreamComponents(region: region, visualProfile: visualProfile)
        case .appWindow:
            guard let contentFilter else { throw ScreenShareStreamError.missingContentFilter }
            return makeSharedContentStreamComponents(contentFilter, visualProfile: visualProfile)
        }
    }

    private func makeDisplayStreamComponents(
        region: CGRect?,
        visualProfile: ScreenShareVisualProfile
    ) async throws -> ScreenShareStreamComponents {
        let shareableContent = try await SCShareableContent.current
        let displayDescriptors = shareableContent.displays.map {
            ScreenShareDisplayDescriptor(
                id: $0.displayID,
                frame: Self.screenFrame(for: $0.displayID) ?? $0.frame,
                pixelWidth: $0.width,
                pixelHeight: $0.height
            )
        }
        let requestedRect = (region ?? preferredFullScreenDisplay(from: displayDescriptors)?.frame ?? CGRect(x: 0, y: 0, width: 1, height: 1)).standardized
        guard requestedRect.width > 0, requestedRect.height > 0 else { throw ScreenShareStreamError.invalidContentRect }

        guard let capturePlan = ScreenShareCaptureGeometry.resolveCapturePlan(
            requestedRect: requestedRect,
            displays: displayDescriptors
        ) else { throw ScreenShareStreamError.invalidContentRect }
        guard let display = shareableContent.displays.first(where: { $0.displayID == capturePlan.displayID }) else { throw ScreenShareStreamError.missingDisplay }
        let outputSize = visualProfile.fittedPixelSize(width: capturePlan.outputWidth, height: capturePlan.outputHeight)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = capturePlan.sourceRect
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configureStream(configuration)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return makeStreamComponents(filter: filter, configuration: configuration)
    }

    private func makeSharedContentStreamComponents(
        _ contentFilter: SCContentFilter,
        visualProfile: ScreenShareVisualProfile
    ) -> ScreenShareStreamComponents {
        let contentInfo = SCShareableContent.info(for: contentFilter)
        let contentRect = contentInfo.contentRect.standardized
        let pixelScale = CGFloat(max(contentInfo.pointPixelScale, 1))

        let outputSize = visualProfile.fittedPixelSize(
            width: max(Int((contentRect.width * pixelScale).rounded(.up)), 1),
            height: max(Int((contentRect.height * pixelScale).rounded(.up)), 1)
        )
        let configuration = SCStreamConfiguration()
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configureStream(configuration)

        return makeStreamComponents(filter: contentFilter, configuration: configuration)
    }

    private func makeStreamComponents(filter: SCContentFilter, configuration: SCStreamConfiguration) -> ScreenShareStreamComponents {
        let delegate = ScreenShareStreamDelegate { [weak self] error in
            self?.handleStreamStopped(error: error)
        }
        return ScreenShareStreamComponents(stream: SCStream(filter: filter, configuration: configuration, delegate: delegate), delegate: delegate)
    }

    private func configureStream(_ configuration: SCStreamConfiguration) {
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(seconds: sendFrameInterval, preferredTimescale: 600)
    }

    private func handleStreamStopped(error: Error) {
        guard isActive else { return }
        stream = nil
        streamOutput = nil
        streamDelegate = nil
        isActive = false
        updateHighlight()

        if isConnectedOrConnecting {
            setStatusMessage("Screen sharing stopped.")
        }
        if (error as NSError).code != NSUserCancelledError {
            NotchLog.gemini.debug("Screen stream stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func screenFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }?.frame
    }

    private func preferredFullScreenDisplay(from displays: [ScreenShareDisplayDescriptor]) -> ScreenShareDisplayDescriptor? {
        displays.first { $0.frame.origin.equalTo(.zero) }
        ?? displays.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    fileprivate nonisolated static let jpegContext = CIContext(options: [.useSoftwareRenderer: false])

    fileprivate nonisolated static func encodeJPEG(from pixelBuffer: CVPixelBuffer, maxDimension: CGFloat?, quality: CGFloat = 0.6) -> Data? {
        let originalWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let originalHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scale = maxDimension.map { min(1.0, $0 / max(originalWidth, originalHeight)) } ?? 1.0
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return encodeJPEG(from: ciImage, quality: quality)
    }

    fileprivate nonisolated static func encodeJPEG(from fullImage: CGImage, maxDimension: CGFloat?, quality: CGFloat = 0.6) -> Data? {
        let originalWidth = CGFloat(fullImage.width)
        let originalHeight = CGFloat(fullImage.height)
        let scale = maxDimension.map { min(1.0, $0 / max(originalWidth, originalHeight)) } ?? 1.0
        let ciImage = CIImage(cgImage: fullImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return encodeJPEG(from: ciImage, quality: quality)
    }

    private nonisolated static func encodeJPEG(from ciImage: CIImage, quality: CGFloat) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return jpegContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        )
    }

    @available(macOS 14.0, *)
    private func captureAndEncodeSharedContent(_ contentFilter: SCContentFilter, maxDimension: CGFloat?, quality: CGFloat = 0.6) async -> Data? {
        let contentInfo = SCShareableContent.info(for: contentFilter)
        let contentRect = contentInfo.contentRect.standardized
        guard contentRect.width > 0, contentRect.height > 0 else { return nil }

        let streamConfiguration = SCStreamConfiguration()
        let pixelScale = CGFloat(max(contentInfo.pointPixelScale, 1))
        streamConfiguration.width = max(Int((contentRect.width * pixelScale).rounded(.up)), 1)
        streamConfiguration.height = max(Int((contentRect.height * pixelScale).rounded(.up)), 1)
        streamConfiguration.showsCursor = false

        let image = await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: streamConfiguration) { image, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }

        guard let image else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.encodeJPEG(from: image, maxDimension: maxDimension, quality: quality)
        }.value
    }

    private func setStatusMessage(_ message: String?) {
        statusMessage = message
        onStatusChange?(message)
    }

    private func statusMessage(for mode: ScreenShareMode, selectedFilter: SCContentFilter?) -> String {
        switch mode {
        case .fullScreen:
            return "Sharing full screen."
        case .selectedRegion:
            return "Sharing selected region."
        case .appWindow:
            guard let selectedFilter else {
                return "Sharing selected app or window."
            }
            let style = SCShareableContent.info(for: selectedFilter).style
            switch style {
            case .application:
                return "Sharing selected app."
            case .window:
                return "Sharing selected window."
            default:
                return "Sharing selected content."
            }
        }
    }
}

private final class ScreenShareStreamDelegate: NSObject, SCStreamDelegate {
    private let onStop: @MainActor (Error) -> Void

    init(onStop: @escaping @MainActor (Error) -> Void) {
        self.onStop = onStop
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [onStop] in
            onStop(error)
        }
    }
}

private final class ScreenShareStreamOutput: NSObject, SCStreamOutput {
    private let sendFrameInterval: TimeInterval
    private let maximumLongEdge: CGFloat?
    private let onFrameCaptured: @MainActor (Data) -> Void
    private var nextFrameSendTime: TimeInterval = 0
    private var frameChangeFilter = ScreenShareFrameChangeFilter()

    init(
        sendFrameInterval: TimeInterval,
        maximumLongEdge: Int?,
        onFrameCaptured: @escaping @MainActor (Data) -> Void
    ) {
        self.sendFrameInterval = sendFrameInterval
        self.maximumLongEdge = maximumLongEdge.map(CGFloat.init)
        self.onFrameCaptured = onFrameCaptured
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard shouldEncodeFrame(at: timestamp) else { return }

        guard let jpeg = ScreenShareCoordinator.encodeJPEG(from: pixelBuffer, maxDimension: maximumLongEdge, quality: 0.5),
              frameChangeFilter.shouldSend(jpeg)
        else { return }
        Task { @MainActor [onFrameCaptured] in
            onFrameCaptured(jpeg)
        }
    }

    private func shouldEncodeFrame(at timestamp: TimeInterval) -> Bool {
        guard timestamp >= nextFrameSendTime else { return false }
        nextFrameSendTime = timestamp + sendFrameInterval
        return true
    }
}

extension GeminiMediaResolution {
    var screenShareMediaResolution: ScreenShareMediaResolution {
        switch self {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}
