import AppKit
import NotchFocusCore
@testable import NotchShelfCore
@preconcurrency import UserNotifications

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItemController: StatusItemController?
    private var holdToTalkHotkeyManager: HoldToTalkHotkeyManager?
    private var focusBrowserBridgeServer: FocusBrowserBridgeServer?
    private let singleInstanceCoordinator = SingleInstanceCoordinator()
    lazy var entitlementStore = NotchEntitlementStore()
    lazy var geminiLiveViewModel = GeminiLiveViewModel(entitlementStore: entitlementStore)
    lazy var learningStatsStore = LearningStatsStore()
    lazy var playbackViewModel = MediaProbeViewModel()
    lazy var pomodoroViewModel = PomodoroViewModel(learningStatsStore: learningStatsStore)
    lazy var focusWebsiteBlocklistStore = FocusWebsiteBlocklistStore()
    lazy var shelfViewModel = NotchShelfViewModel()
    lazy var presentationModel = NotchPresentationModel()

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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NotchLog.app.error("Notification authorization error: \(error.localizedDescription)")
            }
        }
        UNUserNotificationCenter.current().delegate = self

        let notchController = NotchWindowController(
            playbackViewModel: playbackViewModel,
            pomodoroViewModel: pomodoroViewModel,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            geminiLiveViewModel: geminiLiveViewModel,
            shelfViewModel: shelfViewModel,
            learningStatsStore: learningStatsStore,
            presentationModel: presentationModel,
            entitlementStore: entitlementStore
        )

        self.notchController = notchController
        self.statusItemController = StatusItemController(windowController: notchController)
        AppSettingsController.shared.configure(
            presentationModel: presentationModel,
            pomodoro: pomodoroViewModel,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            learningStats: learningStatsStore,
            gemini: geminiLiveViewModel,
            entitlementStore: entitlementStore
        )
        let focusBrowserBridgeServer = FocusBrowserBridgeServer(
            pomodoroViewModel: pomodoroViewModel,
            blocklistStore: focusWebsiteBlocklistStore,
            entitlementStore: entitlementStore
        )
        focusBrowserBridgeServer.start()
        self.focusBrowserBridgeServer = focusBrowserBridgeServer

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

        refreshProStatus()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshProStatus()
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
        statusItemController = nil
        holdToTalkHotkeyManager = nil
        focusBrowserBridgeServer?.stop()
        focusBrowserBridgeServer = nil
        notchController?.shutdown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let notchController else { return }
        for url in urls {
            NotchCommandRouter.handle(url: url, controller: notchController, entitlementStore: entitlementStore)
        }
    }

    private func activatePrimaryWindow() {
        notchController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshProStatus() {
        Task { @MainActor [weak self] in
            await self?.geminiLiveViewModel.refreshBackendSubscriptionStatus()
        }
    }
}

extension NotchAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
