import AppKit
import NotchFocusCore
import NotchShelfCore
@preconcurrency import UserNotifications

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstanceCoordinator = SingleInstanceCoordinator()
    private lazy var bootstrapper = ApplicationBootstrapper(singleInstanceCoordinator: singleInstanceCoordinator)

    var entitlementStore: NotchEntitlementStore { bootstrapper.environment.entitlementStore }
    var geminiLiveViewModel: GeminiLiveViewModel { bootstrapper.environment.geminiLiveViewModel }
    var learningStatsStore: LearningStatsStore { bootstrapper.environment.learningStatsStore }
    var pomodoroViewModel: PomodoroViewModel { bootstrapper.environment.pomodoroViewModel }
    var focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore { bootstrapper.environment.focusWebsiteBlocklistStore }
    var shortcutStore: ShortcutStore { bootstrapper.environment.shortcutStore }
    var presentationModel: NotchPresentationModel { bootstrapper.environment.presentationModel }
    var shelfViewModel: NotchShelfViewModel { bootstrapper.environment.shelfViewModel }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard singleInstanceCoordinator.shouldTerminateForExistingInstance() else { return }
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapper.start(notificationDelegate: self)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bootstrapper.coordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        bootstrapper.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        bootstrapper.coordinator.handle(urls: urls)
    }
}

extension NotchAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
