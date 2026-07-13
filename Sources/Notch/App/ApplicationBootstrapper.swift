import AppKit
@preconcurrency import UserNotifications

@MainActor
final class ApplicationBootstrapper {
    let environment: NotchAppEnvironment
    let coordinator: ApplicationCoordinator

    private var statusItemController: StatusItemController?
    private var holdToTalkHotkeyManager: HoldToTalkHotkeyManager?
    private var screenObserver: NSObjectProtocol?

    init(singleInstanceCoordinator: SingleInstanceCoordinator) {
        let environment = NotchAppEnvironment()
        self.environment = environment
        coordinator = ApplicationCoordinator(
            environment: environment,
            singleInstanceCoordinator: singleInstanceCoordinator
        )
    }

    func start(notificationDelegate: UNUserNotificationCenterDelegate) {
        NSApp.setActivationPolicy(.accessory)

        AppNotificationManager.setup()
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = notificationDelegate
        Task {
            do {
                _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                NotchLog.app.error("Notification authorization error: \(error.localizedDescription)")
            }
        }

        environment.appSettingsController.configure(
            presentationModel: environment.presentationModel,
            pomodoro: environment.pomodoroViewModel,
            learningStats: environment.learningStatsStore,
            focusCloudSync: environment.focusCloudSyncService,
            portalAccount: environment.portalAccountCoordinator,
            gemini: environment.geminiLiveViewModel,
            entitlementStore: environment.entitlementStore,
            shelf: environment.shelfViewModel
        )

        environment.focusCloudSyncService.start()

        let holdToTalkHotkeyManager = HoldToTalkHotkeyManager()
        holdToTalkHotkeyManager.onPress = { [weak featureCoordinator = environment.featureCoordinator] in
            featureCoordinator?.beginGeminiLiveHoldToTalk()
        }
        holdToTalkHotkeyManager.onRelease = { [weak featureCoordinator = environment.featureCoordinator] in
            featureCoordinator?.endGeminiLiveHoldToTalk()
        }
        self.holdToTalkHotkeyManager = holdToTalkHotkeyManager

        statusItemController = StatusItemController(featureCoordinator: environment.featureCoordinator)

        // Keyboard remapper (Settings → Shortcuts)
        QuickKeyEngine.shared.bootstrap()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak coordinator] _ in
            Task { @MainActor [weak coordinator] in
                coordinator?.screenConfigurationDidChange()
            }
        }

        coordinator.start()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        statusItemController = nil
        holdToTalkHotkeyManager = nil
        QuickKeyEngine.shared.stop()
        coordinator.stop()
        environment.focusCloudSyncService.shutdown()
    }
}
