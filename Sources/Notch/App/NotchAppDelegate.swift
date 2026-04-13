import AppKit
import UserNotifications

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var holdToTalkHotkeyManager: HoldToTalkHotkeyManager?
    private let singleInstanceCoordinator = SingleInstanceCoordinator()

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard singleInstanceCoordinator.shouldTerminateForExistingInstance() else { return }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        singleInstanceCoordinator.registerActivationHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.activatePrimaryWindow()
            }
        }

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
        let geminiLiveViewModel = GeminiLiveViewModel()
        let shelfViewModel = NotchShelfViewModel()
        let presentationModel = NotchPresentationModel()
        let notchController = NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel
        )

        self.notchController = notchController

        let holdToTalkHotkeyManager = HoldToTalkHotkeyManager()
        holdToTalkHotkeyManager.onPress = { [weak notchController] in
            notchController?.beginGeminiLiveHoldToTalk()
        }
        holdToTalkHotkeyManager.onRelease = { [weak notchController] in
            notchController?.endGeminiLiveHoldToTalk()
        }
        self.holdToTalkHotkeyManager = holdToTalkHotkeyManager

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
        singleInstanceCoordinator.unregisterActivationHandler()
        holdToTalkHotkeyManager = nil
        notchController?.shutdown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let notchController else { return }
        for url in urls {
            NotchCommandRouter.handle(url: url, controller: notchController)
        }
    }

    private func activatePrimaryWindow() {
        notchController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension NotchAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
