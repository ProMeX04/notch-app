import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    let playbackViewModel: MusicProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let geminiLiveViewModel: GeminiLiveViewModel
    let shelfViewModel: NotchShelfViewModel
    let learningStatsStore: LearningStatsStore
    let presentationModel: NotchPresentationModel

    private let hostingView: NSHostingView<MusicNotchView>
    private let window: NotchFloatingPanel
    private var cancellables = Set<AnyCancellable>()
    private let transcriptOverlay = TranscriptOverlayWindowController()
    private let liveChatInputPanel = GeminiLiveChatInputWindowController()
    private let geminiSecretsFloatingPanel = GeminiSecretsFloatingPanelController()

    private(set) var isVisible = true

    init(
        playbackViewModel: MusicProbeViewModel,
        pomodoroViewModel: PomodoroViewModel,
        geminiLiveViewModel: GeminiLiveViewModel,
        shelfViewModel: NotchShelfViewModel,
        learningStatsStore: LearningStatsStore,
        presentationModel: NotchPresentationModel
    ) {
        self.playbackViewModel = playbackViewModel
        self.pomodoroViewModel = pomodoroViewModel
        self.geminiLiveViewModel = geminiLiveViewModel
        self.shelfViewModel = shelfViewModel
        self.learningStatsStore = learningStatsStore
        self.presentationModel = presentationModel

        let initialScreen = NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: initialScreen)
        let initialFrame = NotchMetrics.windowFrame(on: initialScreen)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let window = NotchFloatingPanel(
            contentRect: initialFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        self.window = window
        self.hostingView = NSHostingView(
            rootView: MusicNotchView(
                playback: playbackViewModel,
                pomodoro: pomodoroViewModel,
                gemini: geminiLiveViewModel,
                shelf: shelfViewModel,
                learningStats: learningStatsStore,
                presentationModel: presentationModel
            )
        )

        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        presentationModel.$hideInFullscreen
            .sink { [weak window] hide in
                guard let window = window else { return }
                var behavior: NSWindow.CollectionBehavior = [
                    .stationary,
                    .ignoresCycle
                ]
                if hide {
                    behavior.insert(.moveToActiveSpace)
                } else {
                    behavior.insert(.canJoinAllSpaces)
                    behavior.insert(.fullScreenAuxiliary)
                }
                window.collectionBehavior = behavior
            }
            .store(in: &cancellables)

        transcriptOverlay.setPreferredScreen(initialScreen)
        transcriptOverlay.observe(gemini: geminiLiveViewModel)
        liveChatInputPanel.setPreferredScreen(initialScreen)
        liveChatInputPanel.observe(gemini: geminiLiveViewModel)
        geminiSecretsFloatingPanel.setPreferredScreen(initialScreen)
        geminiLiveViewModel.onPresentSecretsPanel = { [weak self] in
            self?.presentSecretsFloatingPanel()
        }
        geminiLiveViewModel.onExecApprovalAttentionRequested = { [weak self] in
            self?.presentExecApproval()
        }
    }

    func show() {
        isVisible = true
        updateWindowFrame(animated: false)
        window.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
        window.orderOut(nil)
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func showPanel(_ panel: NotchPanel) {
        show()
        presentationModel.selectPanel(panel, reveal: true)
    }

    func togglePinned() {
        presentationModel.togglePinned()
    }

    func setPinned(_ pinned: Bool) {
        guard presentationModel.isPinnedOpen != pinned else { return }
        presentationModel.togglePinned()
    }

    func reposition() {
        updateWindowFrame(animated: false)
    }

    func shutdown() {
        hide()
        transcriptOverlay.stopObserving()
        liveChatInputPanel.stopObserving()
        geminiSecretsFloatingPanel.shutdown()
        geminiLiveViewModel.onPresentSecretsPanel = nil
        shelfViewModel.shutdown()
        playbackViewModel.shutdown()
        pomodoroViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }

    func showMusicPanel() {
        showPanel(.music)
    }

    func showPomodoroPanel() {
        showPanel(.focus)
    }

    func togglePomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.toggleRunning()
    }

    func resetPomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.reset()
    }

    func showFocusPanel() {
        showPanel(.focus)
    }

    func showTalkPanel() {
        showPanel(.talk)
    }

    /// Floating panels for API keys (status bar / tools) — not in the notch.
    func presentSecretsFloatingPanel() {
        NSApp.activate(ignoringOtherApps: true)
        geminiSecretsFloatingPanel.present(gemini: geminiLiveViewModel)
    }

    func presentManageKeysFromStatusMenu() {
        presentSecretsFloatingPanel()
    }

    func presentExecApproval() {
        show()
        presentationModel.selectPanel(.talk, reveal: true)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    func showShelfPanel() {
        showPanel(.shelf)
    }

    func toggleGeminiLive() {
        showTalkPanel()
        geminiLiveViewModel.toggleConnection()
    }

    func connectGeminiLive() {
        showTalkPanel()
        geminiLiveViewModel.connectIfNeeded()
    }

    func disconnectGeminiLive() {
        geminiLiveViewModel.disconnectIfNeeded()
    }

    func muteGeminiLive() {
        geminiLiveViewModel.setInputMode(.openMic)
        geminiLiveViewModel.setOpenMicrophoneEnabled(false)
    }

    func unmuteGeminiLive() {
        geminiLiveViewModel.setInputMode(.openMic)
        geminiLiveViewModel.setOpenMicrophoneEnabled(true)
    }

    func toggleGeminiLiveMicrophone() {
        geminiLiveViewModel.toggleMicrophone()
    }

    func beginGeminiLiveHoldToTalk() {
        geminiLiveViewModel.beginHoldToTalk()
    }

    func endGeminiLiveHoldToTalk() {
        geminiLiveViewModel.endHoldToTalk()
    }

    func setGeminiLiveCaptionsEnabled(_ enabled: Bool) {
        geminiLiveViewModel.setTranscriptOverlayEnabled(enabled)
    }

    func toggleGeminiLiveCaptions() {
        geminiLiveViewModel.setTranscriptOverlayEnabled(!geminiLiveViewModel.showTranscriptOverlay)
    }

    func startFullScreenShare() {
        geminiLiveViewModel.startFullScreenSharing()
    }

    func startRegionScreenShare() {
        geminiLiveViewModel.startRegionScreenSharing()
    }

    func startWindowScreenShare() {
        geminiLiveViewModel.startWindowSharing()
    }

    func stopScreenShare() {
        geminiLiveViewModel.stopScreenSharing()
    }

    func showImageOverlay(query: String, caption: String?, orientation: String?) {
        geminiLiveViewModel.showDisplayedImageOverlay(query: query, caption: caption, orientation: orientation)
    }

    func showImageOverlay(url: URL, query: String?, caption: String?) {
        geminiLiveViewModel.showDisplayedImageOverlay(url: url, query: query, caption: caption)
    }

    func clearImageOverlay() {
        geminiLiveViewModel.clearDisplayedImageOverlay()
    }

    func configurePomodoro(duration: String?, breakDuration: String?) throws {
        let focusSeconds = try resolvedPomodoroSeconds(
            from: duration,
            fallbackSeconds: pomodoroViewModel.focusDurationSeconds,
            parameterName: "duration"
        )
        let breakSeconds = try resolvedPomodoroSeconds(
            from: breakDuration,
            fallbackSeconds: pomodoroViewModel.breakDurationSeconds,
            parameterName: "break"
        )
        pomodoroViewModel.updateCurrentDurations(focusSeconds: focusSeconds, breakSeconds: breakSeconds)
    }

    func startPomodoro(duration: String? = nil, breakDuration: String? = nil) throws {
        try configurePomodoro(duration: duration, breakDuration: breakDuration)
        try performPomodoroAction(action: .start)
    }

    func pausePomodoro() throws {
        try performPomodoroAction(action: .pause)
    }

    func resumePomodoro() throws {
        try performPomodoroAction(action: .resume)
    }

    func resetPomodoroSession() throws {
        try performPomodoroAction(action: .reset)
    }

    func skipPomodoroPhase() {
        pomodoroViewModel.skipPhase()
    }

    func playMedia() {
        playbackViewModel.play()
    }

    func pauseMedia() {
        playbackViewModel.pause()
    }

    func toggleMediaPlayback() {
        playbackViewModel.togglePlay()
    }

    func stopMedia() {
        playbackViewModel.stop()
    }

    func nextMediaTrack() {
        playbackViewModel.nextTrack()
    }

    func previousMediaTrack() {
        playbackViewModel.previousTrack()
    }

    func setMediaVolume(_ level: Double) {
        playbackViewModel.setVolume(to: min(max(level / 100.0, 0), 1))
    }

    func skipMedia(seconds: Double) {
        playbackViewModel.skip(seconds: seconds)
    }

    func openCurrentMediaApp() {
        playbackViewModel.openCurrentApp()
    }

    func togglePomodoroSession() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.toggleRunning()
    }

    func resetPomodoroFromUI() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.reset()
    }

    func updateWindowFrame(animated: Bool) {
        let currentScreen = window.screen ?? NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: currentScreen)
        let frame = NotchMetrics.windowFrame(on: currentScreen)

        window.setFrame(frame, display: true, animate: animated)
        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize)
        transcriptOverlay.setPreferredScreen(currentScreen)
        liveChatInputPanel.setPreferredScreen(currentScreen)
        geminiSecretsFloatingPanel.setPreferredScreen(currentScreen)

        if isVisible {
            window.orderFrontRegardless()
        }
    }

    private func performPomodoroAction(action: FocusCommandAction) throws {
        try action.apply(
            isRunning: pomodoroViewModel.isRunning,
            hasActiveSession: pomodoroViewModel.hasActiveSession,
            start: { pomodoroViewModel.start() },
            pause: { pomodoroViewModel.pause() },
            reset: { pomodoroViewModel.reset() }
        )
    }

    private func resolvedPomodoroSeconds(from raw: String?, fallbackSeconds: Int, parameterName: String) throws -> Int {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackSeconds
        }
        guard let seconds = DurationParser.parse(raw), seconds > 0 else {
            throw NotchFocusCommandError.invalidParameter(parameterName, raw)
        }
        return seconds
    }
}

private enum FocusCommandAction {
    case start
    case pause
    case resume
    case reset

    func apply(
        isRunning: Bool,
        hasActiveSession: Bool,
        start: () -> Void,
        pause: () -> Void,
        reset: () -> Void
    ) throws {
        switch self {
        case .start:
            if isRunning || hasActiveSession {
                reset()
            }
            start()
        case .pause:
            guard isRunning else { return }
            pause()
        case .resume:
            guard !isRunning else { return }
            guard hasActiveSession else {
                throw NotchFocusCommandError.resumeWithoutSession
            }
            start()
        case .reset:
            reset()
        }
    }
}

private enum NotchFocusCommandError: LocalizedError {
    case resumeWithoutSession
    case invalidParameter(String, String)

    var errorDescription: String? {
        switch self {
        case .resumeWithoutSession:
            return "Can't resume because Pomodoro has no active session."
        case let .invalidParameter(name, value):
            return "Couldn't parse \(name) value '\(value)'."
        }
    }
}
