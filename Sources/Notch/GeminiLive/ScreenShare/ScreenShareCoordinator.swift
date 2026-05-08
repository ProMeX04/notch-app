import AppKit
import Combine
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenShareMode {
    case fullScreen
    case selectedRegion
    case appWindow
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
    private var captureTask: Task<Void, Never>?
    private var contentFilter: SCContentFilter?

    var onFrameCaptured: (@MainActor (Data) -> Void)?
    var onStatusChange: (@MainActor (String?) -> Void)?
    var onErrorMessageChange: (@MainActor (String?) -> Void)?
    var connectionStateProvider: (@MainActor () -> GeminiLiveConnectionState)?

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
        setStatusMessage("Drag to select a screen region. Press Esc to cancel.")

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
        captureTask?.cancel()
        captureTask = nil
        isActive = false
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

        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                guard let self else { break }

                guard let jpeg = await self.captureAndEncodeScreen(
                    region: self.selectedRegion,
                    contentFilter: self.contentFilter
                ) else { continue }

                self.updateHighlight()
                self.onFrameCaptured?(jpeg)
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

    private func captureAndEncodeScreen(region: CGRect?, contentFilter: SCContentFilter?) async -> Data? {
        if #available(macOS 14.0, *), let contentFilter {
            return await captureAndEncodeSharedContent(contentFilter)
        }

        return await captureAndEncodeDisplayRegion(region)
    }

    private func captureAndEncodeDisplayRegion(_ region: CGRect?) async -> Data? {
        let requestedRect = (region ?? NSScreen.main.map { screen in
            CGRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
        } ?? CGRect(x: 0, y: 0, width: 1, height: 1)).standardized
        guard requestedRect.width > 0, requestedRect.height > 0 else { return nil }

        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = Self.bestDisplay(in: shareableContent.displays, for: requestedRect) else { return nil }

            let displayFrame = display.frame.standardized
            let sourceRect = requestedRect.intersection(displayFrame).standardized
            guard !sourceRect.isNull, sourceRect.width > 0, sourceRect.height > 0 else { return nil }

            let streamConfiguration = SCStreamConfiguration()
            let scaleX = CGFloat(display.width) / max(displayFrame.width, 1)
            let scaleY = CGFloat(display.height) / max(displayFrame.height, 1)
            streamConfiguration.sourceRect = sourceRect
            streamConfiguration.width = max(Int((sourceRect.width * scaleX).rounded(.up)), 1)
            streamConfiguration.height = max(Int((sourceRect.height * scaleY).rounded(.up)), 1)
            streamConfiguration.showsCursor = false

            let contentFilter = SCContentFilter(display: display, excludingWindows: [])
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
                Self.encodeJPEG(from: image)
            }.value
        } catch {
            NotchLog.gemini.debug("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static let jpegContext = CIContext(options: [.useSoftwareRenderer: false])

    private nonisolated static func bestDisplay(in displays: [SCDisplay], for rect: CGRect) -> SCDisplay? {
        displays.max { lhs, rhs in
            intersectionArea(lhs.frame, rect) < intersectionArea(rhs.frame, rect)
        }
    }

    private nonisolated static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private nonisolated static func encodeJPEG(from fullImage: CGImage) -> Data? {
        let maxWidth: CGFloat = 1280
        let originalWidth = CGFloat(fullImage.width)
        let scale = min(1.0, maxWidth / originalWidth)

        let ciImage = CIImage(cgImage: fullImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return jpegContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
        )
    }

    @available(macOS 14.0, *)
    private func captureAndEncodeSharedContent(_ contentFilter: SCContentFilter) async -> Data? {
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
            Self.encodeJPEG(from: image)
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
