import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    let playbackViewModel: MusicProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let countdownViewModel: CountdownViewModel
    let counterViewModel: CounterViewModel
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
        countdownViewModel: CountdownViewModel,
        counterViewModel: CounterViewModel,
        geminiLiveViewModel: GeminiLiveViewModel,
        shelfViewModel: NotchShelfViewModel,
        learningStatsStore: LearningStatsStore,
        presentationModel: NotchPresentationModel
    ) {
        self.playbackViewModel = playbackViewModel
        self.pomodoroViewModel = pomodoroViewModel
        self.countdownViewModel = countdownViewModel
        self.counterViewModel = counterViewModel
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
                countdown: countdownViewModel,
                counter: counterViewModel,
                gemini: geminiLiveViewModel,
                shelf: shelfViewModel,
                learningStats: learningStatsStore,
                presentationModel: presentationModel
            )
        )

        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

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
        countdownViewModel.shutdown()
        counterViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }

    func showMusicPanel() {
        showPanel(.music)
    }

    func showPomodoroPanel() {
        showPanel(.focus)
        presentationModel.selectedFocusTool = .pomodoro
    }

    func showCountdownPanel() {
        showPanel(.focus)
        presentationModel.selectedFocusTool = .countdown
    }

    func togglePomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        presentationModel.selectedFocusTool = .pomodoro
        pomodoroViewModel.toggleRunning()
    }

    func resetPomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        presentationModel.selectedFocusTool = .pomodoro
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
        geminiLiveViewModel.setMicrophoneEnabled(false)
    }

    func unmuteGeminiLive() {
        geminiLiveViewModel.setMicrophoneEnabled(true)
    }

    func toggleGeminiLiveMicrophone() {
        geminiLiveViewModel.toggleMicrophone()
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

    func showFocusTool(_ tool: FocusTool?) {
        showFocusPanel()
        if let tool {
            presentationModel.selectedFocusTool = tool
        }
    }

    private func resolvedFocusTool(_ tool: FocusTool?) -> FocusTool {
        tool ?? presentationModel.selectedFocusTool
    }

    func toggleFocusTool(_ tool: FocusTool?) {
        let targetTool = resolvedFocusTool(tool)
        presentationModel.selectedFocusTool = targetTool
        toggleSelectedFocusTool()
    }

    func configureFocusTool(_ tool: FocusTool?, duration: String?, breakDuration: String?) throws {
        switch resolvedFocusTool(tool) {
        case .pomodoro:
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
        case .countdown:
            if breakDuration != nil {
                throw NotchFocusCommandError.unsupportedBreakDuration
            }
            guard let duration, !duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard countdownViewModel.setDuration(from: duration) else {
                throw NotchFocusCommandError.invalidDuration(duration)
            }
        case .counter:
            if duration != nil || breakDuration != nil {
                throw NotchFocusCommandError.counterDoesNotUseDurations
            }
        }
    }

    func startFocusTool(_ tool: FocusTool?, duration: String? = nil, breakDuration: String? = nil) throws {
        try configureFocusTool(tool, duration: duration, breakDuration: breakDuration)
        try performFocusAction(tool: tool, action: .start)
    }

    func pauseFocusTool(_ tool: FocusTool?) throws {
        try performFocusAction(tool: tool, action: .pause)
    }

    func resumeFocusTool(_ tool: FocusTool?) throws {
        try performFocusAction(tool: tool, action: .resume)
    }

    func resetFocusTool(_ tool: FocusTool?) throws {
        try performFocusAction(tool: tool, action: .reset)
    }

    func skipFocusTool(_ tool: FocusTool?) throws {
        switch resolvedFocusTool(tool) {
        case .pomodoro:
            pomodoroViewModel.skipPhase()
        case .countdown, .counter:
            throw NotchFocusCommandError.skipUnsupported(resolvedFocusTool(tool).rawValue)
        }
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

    func toggleSelectedFocusTool() {
        presentationModel.selectPanel(.focus, reveal: true)

        switch presentationModel.selectedFocusTool {
        case .pomodoro:
            pomodoroViewModel.toggleRunning()
        case .countdown:
            countdownViewModel.toggleRunning()
        case .counter:
            counterViewModel.toggleRunning()
        }
    }

    func resetSelectedFocusTool() {
        presentationModel.selectPanel(.focus, reveal: true)

        switch presentationModel.selectedFocusTool {
        case .pomodoro:
            pomodoroViewModel.reset()
        case .countdown:
            countdownViewModel.reset()
        case .counter:
            counterViewModel.reset()
        }
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

    private func performFocusAction(tool: FocusTool?, action: FocusCommandAction) throws {
        switch resolvedFocusTool(tool) {
        case .pomodoro:
            try action.apply(
                isRunning: pomodoroViewModel.isRunning,
                hasActiveSession: pomodoroViewModel.hasActiveSession,
                start: { pomodoroViewModel.start() },
                pause: { pomodoroViewModel.pause() },
                reset: { pomodoroViewModel.reset() }
            )
        case .countdown:
            try action.apply(
                isRunning: countdownViewModel.isRunning,
                hasActiveSession: countdownViewModel.hasActiveSession,
                start: { countdownViewModel.start() },
                pause: { countdownViewModel.pause() },
                reset: { countdownViewModel.reset() }
            )
        case .counter:
            try action.apply(
                isRunning: counterViewModel.isRunning,
                hasActiveSession: counterViewModel.hasActiveSession,
                start: { counterViewModel.start() },
                pause: { counterViewModel.pause() },
                reset: { counterViewModel.reset() }
            )
        }
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
    case invalidDuration(String)
    case invalidParameter(String, String)
    case unsupportedBreakDuration
    case counterDoesNotUseDurations
    case skipUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .resumeWithoutSession:
            return "Can't resume because the selected focus tool has no active session."
        case let .invalidDuration(value):
            return "Couldn't parse duration '\(value)'."
        case let .invalidParameter(name, value):
            return "Couldn't parse \(name) value '\(value)'."
        case .unsupportedBreakDuration:
            return "Break duration is only supported for pomodoro."
        case .counterDoesNotUseDurations:
            return "Stopwatch does not use durations."
        case let .skipUnsupported(tool):
            return "Skip is not supported for \(tool)."
        }
    }
}
