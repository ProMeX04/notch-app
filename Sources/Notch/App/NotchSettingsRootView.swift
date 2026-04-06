import SwiftUI

/// macOS **Settings** window (⌘,). Most controls live in the notch and menu bar; this is a minimal shell so the app builds and users have a standard settings entry.
struct NotchSettingsRootView: View {
    var body: some View {
        Form {
            Section {
                Text("Use the Notch menu bar icon for panels, keys, and controls.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notch")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 200)
    }
}
