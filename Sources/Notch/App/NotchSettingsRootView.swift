import SwiftUI

/// macOS **Settings** window for app-wide shortcuts and controls.
struct NotchSettingsRootView: View {
    @State private var shortcut = HoldToTalkShortcutStore.load()

    var body: some View {
        Form {
            Section {
                Text("Use the Notch interface for panels, keys, and controls.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notch")
            }

            Section {
                HoldToTalkShortcutRecorderView(
                    shortcut: $shortcut,
                    helperText: "Used only in Push to Talk mode while Gemini Live is connected. Shortcuts must include at least one modifier key."
                )
            } header: {
                Text("Hold To Talk")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 260)
    }
}
