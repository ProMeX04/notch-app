import AppKit
import UserNotifications

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppNotificationManager.setup()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .timeSensitive]) { granted, error in
            if let error = error {
                NotchLog.app.error("Notification authorization error: \(error.localizedDescription)")
            }
        }
        UNUserNotificationCenter.current().delegate = self

        let learningStatsStore = LearningStatsStore()
        let playbackViewModel = MusicProbeViewModel()
        let pomodoroViewModel = PomodoroViewModel(learningStatsStore: learningStatsStore)
        let countdownViewModel = CountdownViewModel(learningStatsStore: learningStatsStore)
        let counterViewModel = CounterViewModel(learningStatsStore: learningStatsStore)
        let geminiLiveViewModel = GeminiLiveViewModel()
        let shelfViewModel = NotchShelfViewModel()
        geminiLiveViewModel.pomodoro = pomodoroViewModel
        geminiLiveViewModel.countdown = countdownViewModel
        geminiLiveViewModel.counter = counterViewModel
        geminiLiveViewModel.playback = playbackViewModel
        let presentationModel = NotchPresentationModel()
        let notchController = NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            countdownViewModel: countdownViewModel,
            counterViewModel: counterViewModel,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel
        )

        self.notchController = notchController
        self.statusItemController = StatusItemController(windowController: notchController)

        notchController.show()
        configureDebugLaunchBehavior(using: notchController)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc
    private func screenConfigurationDidChange() {
        notchController?.reposition()
    }

    private func configureDebugLaunchBehavior(using notchController: NotchWindowController) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOTCH_DEBUG_AUTOSTART_POMODORO"] == "1" else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            notchController.showPomodoroPanel()

            guard environment["NOTCH_DEBUG_START_PAUSED"] != "1" else { return }
            notchController.togglePomodoro()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.shutdown()
    }
}

extension NotchAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
