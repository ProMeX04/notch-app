import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(NotchAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsView(
                presentationModel: appDelegate.presentationModel,
                pomodoro: appDelegate.pomodoroViewModel,
                focusWebsiteBlocklistStore: appDelegate.focusWebsiteBlocklistStore,
                learningStats: appDelegate.learningStatsStore,
                gemini: appDelegate.geminiLiveViewModel
            )
        }
    }
}
