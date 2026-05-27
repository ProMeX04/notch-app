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
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NotchLog.app.error("Notification authorization error: \(error.localizedDescription)")
            }
        }
        notificationCenter.delegate = notificationDelegate

        environment.appSettingsController.configure(
            presentationModel: environment.presentationModel,
            pomodoro: environment.pomodoroViewModel,
            focusWebsiteBlocklistStore: environment.focusWebsiteBlocklistStore,
            learningStats: environment.learningStatsStore,
            focusCloudSync: environment.focusCloudSyncService,
            portalAccount: environment.portalAccountCoordinator,
            gemini: environment.geminiLiveViewModel,
            entitlementStore: environment.entitlementStore,
            shortcutStore: environment.shortcutStore,
            shelf: environment.shelfViewModel
        )

        environment.focusBrowserBridgeServer.start()
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
        coordinator.stop()
        environment.focusCloudSyncService.shutdown()
    }
}
