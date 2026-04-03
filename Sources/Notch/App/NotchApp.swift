import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(NotchAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
