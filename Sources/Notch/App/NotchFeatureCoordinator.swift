import AppKit
import NotchFocusCore
import SwiftUI

@MainActor
protocol NotchCommandHandling: AnyObject {
    func showPanel(_ panel: NotchPanel)
    func show()
    func hide()
    func toggleVisibility()
    func togglePinned()
    func setPinned(_ pinned: Bool)
    func showFocusPanel()
    func showTalkPanel()
    func showShelfPanel()
    func showShortcutsPanel()
    func togglePomodoro()
    func resetPomodoro()
    func toggleGeminiLive()
    func connectGeminiLive()
    func disconnectGeminiLive()
    func muteGeminiLive()
    func unmuteGeminiLive()
    func toggleGeminiLiveMicrophone()
    func setGeminiLiveCaptionsEnabled(_ enabled: Bool)
    func toggleGeminiLiveCaptions()
    func startFullScreenShare()
    func startRegionScreenShare()
    func startWindowScreenShare()
    func stopScreenShare()
    func configurePomodoro(duration: String?, breakDuration: String?, longBreakDuration: String?) throws
    func startPomodoro(duration: String?, breakDuration: String?, longBreakDuration: String?, cycleCount: String?) throws
    func pausePomodoro() throws
    func resumePomodoro() throws
    func resetPomodoroSession() throws
    func skipPomodoroPhase()
    func playMedia()
    func pauseMedia()
    func toggleMediaPlayback()
    func stopMedia()
    func nextMediaTrack()
    func previousMediaTrack()
    func setMediaVolume(_ level: Double)
    func skipMedia(seconds: Double)
    func openCurrentMediaApp()
    func openAppSettings()
    func handleOAuthCallback(_ url: URL)
}

@MainActor
final class NotchFeatureCoordinator: NotchCommandHandling {
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let geminiLiveViewModel: GeminiLiveViewModel
    let presentationModel: NotchPresentationModel

    private let windowController: NotchWindowController
    private let appSettingsController: AppSettingsControlling

    init(
        windowController: NotchWindowController,
        playbackViewModel: MediaProbeViewModel,
        pomodoroViewModel: PomodoroViewModel,
        geminiLiveViewModel: GeminiLiveViewModel,
        presentationModel: NotchPresentationModel,
        appSettingsController: AppSettingsControlling = AppSettingsController.shared
    ) {
        self.windowController = windowController
        self.playbackViewModel = playbackViewModel
        self.pomodoroViewModel = pomodoroViewModel
        self.geminiLiveViewModel = geminiLiveViewModel
        self.presentationModel = presentationModel
        self.appSettingsController = appSettingsController
    }

    var isVisible: Bool {
        windowController.isVisible
    }

    func start() {
        geminiLiveViewModel.onExecApprovalAttentionRequested = { [weak self] in
            self?.windowController.presentExecApproval()
        }
        geminiLiveViewModel.onOpenAppSettingsRequested = { [weak self] in
            self?.appSettingsController.open(tab: .talk)
        }
    }

    func stop() {
        geminiLiveViewModel.onExecApprovalAttentionRequested = nil
        geminiLiveViewModel.onOpenAppSettingsRequested = nil
    }

    func showPanel(_ panel: NotchPanel) {
        windowController.show()
        presentationModel.selectPanel(panel, reveal: true)
    }

    func show() {
        windowController.show()
    }

    func hide() {
        windowController.hide()
    }

    func toggleVisibility() {
        windowController.toggleVisibility()
    }

    func togglePinned() {
        presentationModel.togglePinned()
    }

    func setPinned(_ pinned: Bool) {
        guard presentationModel.isPinnedOpen != pinned else { return }
        presentationModel.togglePinned()
    }

    func showFocusPanel() {
        showPanel(.focus)
    }

    func showTalkPanel() {
        showPanel(.talk)
    }

    func showShelfPanel() {
        showPanel(.shelf)
    }

    func showShortcutsPanel() {
        showPanel(.shortcuts)
    }

    func togglePomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.toggleRunning()
    }

    func resetPomodoro() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.reset()
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

    func configurePomodoro(duration: String?, breakDuration: String?, longBreakDuration: String? = nil) throws {
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
        let longBreakSeconds = try resolvedPomodoroSeconds(
            from: longBreakDuration,
            fallbackSeconds: pomodoroViewModel.longBreakDurationSeconds,
            parameterName: "long-break"
        )
        pomodoroViewModel.updateCurrentDurations(focusSeconds: focusSeconds, breakSeconds: breakSeconds)
        pomodoroViewModel.updateLongBreakDuration(seconds: longBreakSeconds)
    }

    func startPomodoro(duration: String? = nil, breakDuration: String? = nil, longBreakDuration: String? = nil, cycleCount: String? = nil) throws {
        try configurePomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
        if let cycleCount, let count = Int(cycleCount.trimmingCharacters(in: .whitespacesAndNewlines)) {
            pomodoroViewModel.updateSessionsBeforeLongBreak(count: count)
        }
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

    func openAppSettings() {
        appSettingsController.open(tab: .general)
    }

    func handleOAuthCallback(_ url: URL) {
        geminiLiveViewModel.handleBackendOAuthCallback(url)
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
