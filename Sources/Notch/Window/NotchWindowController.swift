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

    func reposition() {
        updateWindowFrame(animated: false)
    }

    func shutdown() {
        hide()
        transcriptOverlay.stopObserving()
        shelfViewModel.shutdown()
        playbackViewModel.shutdown()
        pomodoroViewModel.shutdown()
        countdownViewModel.shutdown()
        counterViewModel.shutdown()
        geminiLiveViewModel.shutdown()
        cancellables.removeAll()
    }

    func showMusicPanel() {
        presentationModel.selectPanel(.music, reveal: true)
    }

    func showPomodoroPanel() {
        presentationModel.selectPanel(.focus, reveal: true)
        presentationModel.selectedFocusTool = .pomodoro
    }

    func showCountdownPanel() {
        presentationModel.selectPanel(.focus, reveal: true)
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
        presentationModel.selectPanel(.focus, reveal: true)
    }

    func showTalkPanel() {
        presentationModel.selectPanel(.talk, reveal: true)
    }

    func showShelfPanel() {
        presentationModel.selectPanel(.shelf, reveal: true)
    }

    func toggleGeminiLive() {
        presentationModel.selectPanel(.talk, reveal: true)
        geminiLiveViewModel.toggleConnection()
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

        if isVisible {
            window.orderFrontRegardless()
        }
    }
}
