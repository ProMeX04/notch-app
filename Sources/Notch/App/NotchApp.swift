import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(NotchAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsView(
                presentationModel: appDelegate.presentationModel,
                pomodoro: appDelegate.pomodoroViewModel,
                learningStats: appDelegate.learningStatsStore,
                focusCloudSync: appDelegate.focusCloudSyncService,
                portalAccount: appDelegate.portalAccountCoordinator,
                gemini: appDelegate.geminiLiveViewModel,
                entitlementStore: appDelegate.entitlementStore,
                shelf: appDelegate.shelfViewModel
            )
        }
    }
}
