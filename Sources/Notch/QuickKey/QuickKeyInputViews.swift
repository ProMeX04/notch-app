import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Type `cmd+b` or record via keyboard icon. Text is authoritative on Save.
struct QuickKeybindInput: View {
    @Binding var keyCode: Int
    @Binding var modifiers: UInt64
    @Binding var text: String
    @Binding var isRecording: Bool
    /// When `detectDoublePress` is true, double-tap while recording sets this to `.double`.
    @Binding var triggerMode: QuickKeyTriggerMode
    var placeholder: String = "cmd+b"
    var allowPureModifiers: Bool = true
    /// Key field only: double-tap while recording → double trigger (no separate mode picker).
    var detectDoublePress: Bool = false
    var tint: Color = .white

    @State private var error: String?
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(isRecording ? (detectDoublePress ? "Press or double-tap…" : "Press keys…") : placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .focused($textFocused)
                .disabled(isRecording)
                .onSubmit { _ = commit(showError: true) }
                .onChange(of: text) { _, _ in error = nil }
                .onChange(of: textFocused) { _, focused in
                    if !focused, !isRecording { _ = commit(showError: false) }
                }

            Text(previewChord)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Button(action: toggleRecord) {
                Image(systemName: isRecording ? "stop.circle.fill" : "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isRecording ? Color.white.opacity(0.85) : tint.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Stop (Esc)" : (detectDoublePress ? "Record key (double-tap = double)" : "Record keys"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isRecording ? Color.white.opacity(0.28) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .background(
            QuickKeyCaptureRepresentable(
                isRecording: $isRecording,
                keyCode: $keyCode,
                modifiers: $modifiers,
                triggerMode: $triggerMode,
                allowPureModifiers: allowPureModifiers,
                detectDoublePress: detectDoublePress
            )
        )
        .onChange(of: isRecording) { was, now in
            QuickKeyEngine.shared.setPaused(now)
            if now {
                error = nil
                textFocused = false
            } else if was {
                text = formattedText()
            }
        }
        .onChange(of: keyCode) { _, _ in
            if isRecording { text = formattedText() }
        }
        .onChange(of: modifiers) { _, _ in
            if isRecording { text = formattedText() }
        }
        .onChange(of: triggerMode) { _, _ in
            if isRecording || !text.isEmpty { text = formattedText() }
        }
        .onDisappear {
            if isRecording {
                isRecording = false
                QuickKeyEngine.shared.setPaused(false)
            }
            _ = commit(showError: false)
        }
        .overlay(alignment: .bottomLeading) {
            if let error {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .offset(y: 16)
            }
        }
    }

    private var previewChord: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, case .success(let r) = QuickKeyShortcutParser.parse(trimmed) {
            let base = QuickKeyChord.display(keyCode: r.keyCode, modifiers: r.modifiers)
            return r.triggerMode == .double ? "\(base) ×2" : base
        }
        let base = QuickKeyChord.display(keyCode: keyCode, modifiers: modifiers)
        return triggerMode == .double ? "\(base) ×2" : base
    }

    private func formattedText() -> String {
        QuickKeyShortcutParser.format(keyCode: keyCode, modifiers: modifiers, mode: triggerMode)
    }

    private func toggleRecord() {
        if isRecording {
            isRecording = false
            _ = commit(showError: false)
        } else {
            textFocused = false
            _ = commit(showError: false)
            isRecording = true
        }
    }

    @discardableResult
    private func commit(showError: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            text = formattedText()
            return true
        }
        switch QuickKeyShortcutParser.parse(trimmed) {
        case .success(let r):
            keyCode = r.keyCode
            modifiers = r.modifiers
            if detectDoublePress {
                triggerMode = r.triggerMode
            } else {
                triggerMode = .single
            }
            text = formattedText()
            error = nil
            return true
        case .failure(let e):
            if showError { error = e.errorDescription }
            return false
        }
    }
}

struct QuickKeyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existing: QuickKeyMapping?
    var tint: Color = .white
    var onSave: (QuickKeyMapping) -> Void

    @State private var name = "Shortcut"
    @State private var isEnabled = true
    @State private var triggerKeyCode = Int(kVK_RightCommand)
    @State private var triggerModifiers: UInt64 = 0
    @State private var triggerMode: QuickKeyTriggerMode = .single
    @State private var targetKeyCode = Int(kVK_ANSI_B)
    @State private var targetModifiers: UInt64 = CGEventFlags.maskCommand.rawValue
    @State private var triggerText = "rcmd"
    @State private var targetText = "cmd+b"
    @State private var whenApp = false
    @State private var appBundleID = ""
    @State private var appDisplayName = ""
    @State private var recordingTrigger = false
    @State private var recordingTarget = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(existing == nil ? "New Shortcut" : "Edit Shortcut")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                Toggle(isOn: $isEnabled) { EmptyView() }
                    .toggleStyle(NotchSwitchStyle(tint: tint))
                    .labelsHidden()
            }

            labeled("Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }

            labeled("Key") {
                QuickKeybindInput(
                    keyCode: $triggerKeyCode,
                    modifiers: $triggerModifiers,
                    text: $triggerText,
                    isRecording: $recordingTrigger,
                    triggerMode: $triggerMode,
                    placeholder: "rcmd  or double-tap",
                    allowPureModifiers: true,
                    detectDoublePress: true,
                    tint: tint
                )
                .onChange(of: recordingTrigger) { _, v in if v { recordingTarget = false } }
            }

            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
            }

            labeled("Send") {
                QuickKeybindInput(
                    keyCode: $targetKeyCode,
                    modifiers: $targetModifiers,
                    text: $targetText,
                    isRecording: $recordingTarget,
                    triggerMode: .constant(.single),
                    placeholder: "cmd+b",
                    allowPureModifiers: false,
                    detectDoublePress: false,
                    tint: tint
                )
                .onChange(of: recordingTarget) { _, v in if v { recordingTrigger = false } }
            }

            labeled("When") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $whenApp) {
                        Text("Always").tag(false)
                        Text("App").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if whenApp {
                        Button(action: showAppPicker) {
                            HStack {
                                Text(appDisplayName.isEmpty ? "Choose app…" : appDisplayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(appDisplayName.isEmpty ? .white.opacity(0.4) : .white.opacity(0.9))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            HStack {
                StandardActionButton(
                    title: "Cancel",
                    tint: tint,
                    variant: .secondary,
                    action: { dismiss() }
                )
                .keyboardShortcut(.cancelAction)
                Spacer()
                StandardActionButton(
                    title: "Save",
                    tint: tint,
                    variant: .primary,
                    isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (whenApp && appBundleID.isEmpty),
                    action: save
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 480)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            content()
        }
    }

    private func load() {
        guard let existing else {
            triggerText = QuickKeyShortcutParser.format(
                keyCode: triggerKeyCode,
                modifiers: triggerModifiers,
                mode: triggerMode
            )
            targetText = QuickKeyShortcutParser.format(keyCode: targetKeyCode, modifiers: targetModifiers)
            return
        }
        name = existing.name
        isEnabled = existing.isEnabled
        triggerKeyCode = existing.triggerKeyCode
        triggerModifiers = existing.triggerModifiers
        triggerMode = existing.triggerMode
        targetKeyCode = existing.targetKeyCode
        targetModifiers = existing.targetModifiers
        triggerText = QuickKeyShortcutParser.format(
            keyCode: triggerKeyCode,
            modifiers: triggerModifiers,
            mode: triggerMode
        )
        targetText = QuickKeyShortcutParser.format(keyCode: targetKeyCode, modifiers: targetModifiers)
        if let bid = existing.appBundleID, !bid.isEmpty {
            whenApp = true
            appBundleID = bid
            appDisplayName = existing.appDisplayName ?? bid
        }
    }

    private func showAppPicker() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let bid = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? bid, bid)
            }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

        let alert = NSAlert()
        alert.messageText = "Choose App"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28), pullsDown: false)
        for (n, bid) in apps {
            popup.addItem(withTitle: n)
            popup.lastItem?.representedObject = bid
            if bid == appBundleID { popup.select(popup.lastItem) }
        }
        alert.accessoryView = popup
        if alert.runModal() == .alertFirstButtonReturn,
           let bid = popup.selectedItem?.representedObject as? String {
            appBundleID = bid
            appDisplayName = popup.selectedItem?.title ?? bid
        }
    }

    private func save() {
        recordingTrigger = false
        recordingTarget = false
        QuickKeyEngine.shared.setPaused(false)

        var tCode = triggerKeyCode
        var tMods = triggerModifiers
        var tMode = triggerMode
        var sCode = targetKeyCode
        var sMods = targetModifiers

        if let err = QuickKeyShortcutParser.apply(
            text: triggerText,
            keyCode: &tCode,
            modifiers: &tMods,
            triggerMode: &tMode
        ) {
            saveError = "Key: \(err)"
            return
        }
        if let err = QuickKeyShortcutParser.apply(text: targetText, keyCode: &sCode, modifiers: &sMods) {
            saveError = "Send: \(err)"
            return
        }

        onSave(QuickKeyMapping(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            triggerKeyCode: tCode,
            triggerModifiers: tMods,
            triggerMode: tMode,
            targetKeyCode: sCode,
            targetModifiers: sMods,
            appBundleID: whenApp ? appBundleID : nil,
            appDisplayName: whenApp ? appDisplayName : nil
        ))
        dismiss()
    }
}
