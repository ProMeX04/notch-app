import AppKit
import Combine
import NotchFocusCore
@testable import NotchShelfCore
import SwiftUI

@MainActor
final class NotchWindowController {
    let playbackViewModel: MediaProbeViewModel
    let pomodoroViewModel: PomodoroViewModel
    let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    let geminiLiveViewModel: GeminiLiveViewModel
    let shelfViewModel: NotchShelfViewModel
    let learningStatsStore: LearningStatsStore
    let presentationModel: NotchPresentationModel

    private let hostingView: NSHostingView<MediaNotchView>
    private let window: NotchFloatingPanel
    private var cancellables = Set<AnyCancellable>()
    private let transcriptOverlay = TranscriptOverlayWindowController()
    private let liveChatInputPanel = GeminiLiveChatInputWindowController()
    private let geminiExecApprovalPanel = GeminiExecApprovalPanelController()

    private(set) var isVisible = true

    init(
        playbackViewModel: MediaProbeViewModel,
        pomodoroViewModel: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        geminiLiveViewModel: GeminiLiveViewModel,
        shelfViewModel: NotchShelfViewModel,
        learningStatsStore: LearningStatsStore,
        presentationModel: NotchPresentationModel
    ) {
        self.playbackViewModel = playbackViewModel
        self.pomodoroViewModel = pomodoroViewModel
        self.focusWebsiteBlocklistStore = focusWebsiteBlocklistStore
        self.geminiLiveViewModel = geminiLiveViewModel
        self.shelfViewModel = shelfViewModel
        self.learningStatsStore = learningStatsStore
        self.presentationModel = presentationModel

        let initialScreen = NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: initialScreen)
        let initialFrame = NotchMetrics.windowFrame(on: initialScreen, selectedPanel: presentationModel.selectedPanel)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        let window = NotchFloatingPanel(
            contentRect: initialFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        self.window = window
        self.hostingView = NSHostingView(
            rootView: MediaNotchView(
                playback: playbackViewModel,
                pomodoro: pomodoroViewModel,
                focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
                gemini: geminiLiveViewModel,
                shelf: shelfViewModel,
                learningStats: learningStatsStore,
                presentationModel: presentationModel
            )
        )

        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize(for: presentationModel.selectedPanel))
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

        Publishers.CombineLatest(presentationModel.$selectedPanel, presentationModel.$isExpanded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)

        transcriptOverlay.setPreferredScreen(initialScreen)
        transcriptOverlay.observe(gemini: geminiLiveViewModel)
        liveChatInputPanel.setPreferredScreen(initialScreen)
        liveChatInputPanel.observe(gemini: geminiLiveViewModel)
        geminiExecApprovalPanel.setPreferredScreen(initialScreen)
        geminiExecApprovalPanel.observe(gemini: geminiLiveViewModel)
        geminiLiveViewModel.onExecApprovalAttentionRequested = { [weak self] in
            self?.presentExecApproval()
        }
        geminiLiveViewModel.onOpenAppSettingsRequested = {
            AppSettingsController.shared.open(tab: .talk)
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
        geminiExecApprovalPanel.stopObserving()
        geminiLiveViewModel.onExecApprovalAttentionRequested = nil
        geminiLiveViewModel.onOpenAppSettingsRequested = nil
        shelfViewModel.shutdown()
        playbackViewModel.shutdown()
        pomodoroViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }

    func showMediaPanel() {
        showPanel(.media)
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

    func presentManageKeysFromStatusMenu() {
        AppSettingsController.shared.open(tab: .talk)
    }

    func presentExecApproval() {
        geminiExecApprovalPanel.present(gemini: geminiLiveViewModel)
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

    func startPomodoro(duration: String? = nil, breakDuration: String? = nil, longBreakDuration: String? = nil) throws {
        try configurePomodoro(duration: duration, breakDuration: breakDuration, longBreakDuration: longBreakDuration)
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

    func setPomodoroPhase(_ rawPhase: String) throws {
        let targetPhase = try resolvedPomodoroPhase(from: rawPhase)
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.setPhase(targetPhase)
    }

    func setPomodoroLongBreak(duration: String) throws {
        let seconds = try resolvedPomodoroSeconds(
            from: duration,
            fallbackSeconds: pomodoroViewModel.longBreakDurationSeconds,
            parameterName: "duration"
        )
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.updateLongBreakDuration(seconds: seconds)
    }

    func setPomodoroCycle(_ rawCount: String) throws {
        guard let count = Int(rawCount.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NotchFocusCommandError.invalidParameter("count", rawCount)
        }
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.updateSessionsBeforeLongBreak(count: count)
    }

    func setPomodoroAutoBreaks(_ mode: FocusToggleMode) {
        presentationModel.selectPanel(.focus, reveal: true)
        switch mode {
        case .on:
            pomodoroViewModel.autoStartBreaks = true
        case .off:
            pomodoroViewModel.autoStartBreaks = false
        case .toggle:
            pomodoroViewModel.autoStartBreaks.toggle()
        }
    }

    func setPomodoroAutoPomodoros(_ mode: FocusToggleMode) {
        presentationModel.selectPanel(.focus, reveal: true)
        switch mode {
        case .on:
            pomodoroViewModel.autoStartPomodoros = true
        case .off:
            pomodoroViewModel.autoStartPomodoros = false
        case .toggle:
            pomodoroViewModel.autoStartPomodoros.toggle()
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

    func openAppSettings() {
        AppSettingsController.shared.open(tab: .general)
    }

    func togglePomodoroSession() {
        presentationModel.selectPanel(.focus, reveal: true)
        pomodoroViewModel.toggleRunning()
    }

    func updateWindowFrame(animated: Bool) {
        let currentScreen = window.screen ?? NotchMetrics.preferredScreen()
        presentationModel.closedNotchSize = NotchMetrics.baseClosedSize(for: currentScreen)
        let frame = NotchMetrics.windowFrame(on: currentScreen, selectedPanel: presentationModel.selectedPanel)

        window.setFrame(frame, display: true, animate: animated)
        hostingView.frame = CGRect(origin: .zero, size: NotchMetrics.windowSize(for: presentationModel.selectedPanel))
        transcriptOverlay.setPreferredScreen(currentScreen)
        liveChatInputPanel.setPreferredScreen(currentScreen)

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

    private func resolvedPomodoroPhase(from raw: String) throws -> PomodoroPhase {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "focus":
            return .focus
        case "short-break", "shortbreak", "short_break", "break":
            return .shortBreak
        case "long-break", "longbreak", "long_break":
            return .longBreak
        default:
            throw NotchFocusCommandError.invalidParameter("phase", raw)
        }
    }

}

enum FocusToggleMode {
    case on
    case off
    case toggle
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
