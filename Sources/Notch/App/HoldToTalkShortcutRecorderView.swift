import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HoldToTalkShortcutRecorderView: View {
    @AppStorage("app_language") private var appLanguage: String = "English"
    @Binding var shortcut: HoldToTalkShortcut
    var title: String? = nil
    var icon: String? = nil
    var helperText: String? = nil
    var isNotchStyle: Bool = false
    var tint: Color = .accentColor

    @State private var isRecording = false
    @State private var validationMessage: String?
    @State private var eventMonitor: Any?

    var body: some View {
        Group {
            if isNotchStyle {
                notchStyleBody
            } else {
                defaultStyleBody
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var notchStyleBody: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.1).cornerRadius(8))
            }
            Text(title ?? Localization.get("Push to Talk", lang: appLanguage))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? Localization.get("Recording...", lang: appLanguage) : shortcut.displayString)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isRecording ? Color(nsColor: .systemRed) : tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06).cornerRadius(6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                             .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if shortcut.displayString != HoldToTalkShortcutStore.defaultShortcut.displayString {
                Button {
                    HoldToTalkShortcutStore.reset()
                    shortcut = HoldToTalkShortcutStore.load()
                    validationMessage = nil
                    stopRecording()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var defaultStyleBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.32))
            }

            HStack(spacing: 10) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isRecording ? "circle.fill" : "keyboard")
                            .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                        Text(isRecording ? Localization.get("Press Shortcut…", lang: appLanguage) : shortcut.displayString)
                            .font(.system(.body, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                Button(Localization.get("Reset", lang: appLanguage)) {
                    HoldToTalkShortcutStore.reset()
                    shortcut = HoldToTalkShortcutStore.load()
                    validationMessage = nil
                    stopRecording()
                }
                .buttonStyle(.bordered)
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: Localization.get("Default: %@", lang: appLanguage), HoldToTalkShortcutStore.defaultShortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func startRecording() {
        validationMessage = nil
        stopRecording()
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleRecording(event)
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection(HoldToTalkShortcut.allowedModifierFlags)
        guard !modifiers.isEmpty else {
            let isVi = appLanguage == "Tiếng Việt"
            validationMessage = isVi ? "Phím tắt phải bao gồm Command, Control, Option, hoặc Shift." : "Shortcut must include Command, Control, Option, or Shift."
            NSSound.beep()
            return
        }

        let recordedShortcut = HoldToTalkShortcut(keyCode: event.keyCode, modifierFlags: modifiers)
        shortcut = recordedShortcut
        HoldToTalkShortcutStore.save(recordedShortcut)
        validationMessage = nil
        stopRecording()
    }
}
