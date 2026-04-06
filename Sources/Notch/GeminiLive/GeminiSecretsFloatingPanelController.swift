import AppKit
import SwiftUI

private final class GeminiSecretsKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class GeminiSecretsWindowDelegate: NSObject, NSWindowDelegate {
    var onWindowWillClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose?()
    }
}

/// AppKit secure field with explicit LTR writing direction (SwiftUI `SecureField` can still mirror on RTL systems).
private struct LTRSecureField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)?

    init(text: Binding<String>, onSubmit: (() -> Void)? = nil) {
        _text = text
        self.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.stringValue = text
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.alignment = .left
        applyLTR(to: field)
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text {
            field.stringValue = text
        }
        applyLTR(to: field)
    }

    private func applyLTR(to field: NSSecureTextField) {
        field.baseWritingDirection = .leftToRight
        if let cell = field.cell as? NSTextFieldCell {
            cell.baseWritingDirection = .leftToRight
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSecureTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
        }
    }
}

// MARK: - Content (standard Settings-style form)

private struct GeminiSecretsFloatingContentView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let mode: GeminiSecretsPanelMode
    let onDismiss: () -> Void

    private var canSaveGeminiOnly: Bool {
        !gemini.apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gemini.isSavingAPIKey
    }

    private var canSaveAll: Bool {
        !gemini.isSavingAPIKey && !gemini.isSavingServiceKeys
    }

    var body: some View {
        Group {
            switch mode {
            case .geminiOnly:
                geminiOnlyForm
            case .allServiceKeys:
                allKeysForm
            }
        }
        // API keys are always entered left-to-right (bullets / cursor follow LTR).
        .environment(\.layoutDirection, .leftToRight)
        .frame(minWidth: 420, minHeight: minContentHeight)
    }

    private var minContentHeight: CGFloat {
        switch mode {
        case .geminiOnly: return 140
        case .allServiceKeys: return 320
        }
    }

    private var geminiOnlyForm: some View {
        Form {
            Section {
                LTRSecureField(text: $gemini.apiKeyText, onSubmit: commitSaveGemini)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Gemini")
            } footer: {
                if let err = gemini.lastErrorMessage, !err.isEmpty {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { commitSaveGemini() }
                    .disabled(!canSaveGeminiOnly)
            }
        }
    }

    private var allKeysForm: some View {
        Form {
            Section("Gemini") {
                LTRSecureField(text: $gemini.apiKeyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Pexels") {
                LTRSecureField(text: $gemini.pexelsAPIKeyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Brave Search") {
                LTRSecureField(text: $gemini.braveSearchAPIKeyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                if let err = gemini.lastErrorMessage, !err.isEmpty {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save keys") { commitSaveAll() }
                    .disabled(!canSaveAll)
            }
        }
    }

    private func commitSaveGemini() {
        guard canSaveGeminiOnly else { return }
        Task {
            if await gemini.saveAPIKey() {
                onDismiss()
            }
        }
    }

    private func commitSaveAll() {
        guard canSaveAll else { return }
        Task {
            if await gemini.saveServiceKeys() {
                onDismiss()
            }
        }
    }
}

@MainActor
final class GeminiSecretsFloatingPanelController {
    private var panel: NSWindow?
    private var hostingView: NSHostingView<GeminiSecretsFloatingContentView>?
    private var moveObserver: NSObjectProtocol?
    private var windowCloseDelegate: GeminiSecretsWindowDelegate?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?
    private var currentMode: GeminiSecretsPanelMode = .geminiOnly

    private let panelWidth: CGFloat = 420
    private let heightGeminiOnly: CGFloat = 140
    private let heightAllKeys: CGFloat = 380
    private let defaultsKey = "dev.notch.gemini-secrets-floating.frame"

    private let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel, hostingView != nil else { return }
        if !frameIntersectsAnyVisibleWorkspace(panel.frame) {
            let sc = screenForPlacement()
            let target = clampFrame(panel.frame, to: sc)
            panel.setFrame(target, display: true)
            hostingView?.frame = panel.contentLayoutRect
        }
    }

    func present(gemini: GeminiLiveViewModel, mode: GeminiSecretsPanelMode) {
        self.gemini = gemini
        currentMode = mode
        gemini.reloadKeyDrafts()
        ensurePanel(gemini: gemini, mode: mode)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.close()
    }

    func shutdown() {
        dismiss()
    }

    // MARK: - Private

    private func handleSecretsWindowClosed() {
        removeMoveObserver()
        if let p = panel {
            p.delegate = nil
        }
        windowCloseDelegate = nil
        panel = nil
        hostingView = nil
        gemini = nil
    }

    private func windowTitle(for mode: GeminiSecretsPanelMode) -> String {
        switch mode {
        case .geminiOnly: return "Gemini API Key"
        case .allServiceKeys: return "Service Keys"
        }
    }

    private func contentHeight(for mode: GeminiSecretsPanelMode) -> CGFloat {
        switch mode {
        case .geminiOnly: return heightGeminiOnly
        case .allServiceKeys: return heightAllKeys
        }
    }

    private func defaultFrame(on screen: NSScreen, mode: GeminiSecretsPanelMode) -> CGRect {
        let vf = screen.visibleFrame
        let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight(for: mode))
        let outer = NSWindow.frameRect(forContentRect: contentRect, styleMask: windowStyle)
        let x = vf.midX - outer.width / 2
        let y = vf.minY + 72
        return CGRect(x: x, y: y, width: outer.width, height: outer.height)
    }

    private func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveFrame(_ frame: CGRect) {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height],
            forKey: defaultsKey
        )
    }

    private func dominantScreen(forWindowFrame windowFrame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.frame)
            let area = max(0, inter.width) * max(0, inter.height)
            if area > bestArea {
                bestArea = area
                best = s
            }
        }
        return best
    }

    private func clampFrame(_ frame: CGRect, to screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var f = frame
        let minVisible: CGFloat = 48
        f.origin.x = min(max(f.origin.x, vf.minX - f.width + minVisible), vf.maxX - minVisible)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - minVisible)
        return f
    }

    private func frameIntersectsAnyVisibleWorkspace(_ windowFrame: CGRect) -> Bool {
        let minOverlap: CGFloat = 32
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.visibleFrame)
            if inter.width >= minOverlap, inter.height >= minOverlap {
                return true
            }
        }
        return false
    }

    private func screenForPlacement() -> NSScreen {
        preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func removeMoveObserver() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
    }

    private func ensurePanel(gemini: GeminiLiveViewModel, mode: GeminiSecretsPanelMode) {
        let sc = screenForPlacement()
        let onDismiss: () -> Void = { [weak self] in
            guard let self else { return }
            self.dismiss()
        }

        if let hv = hostingView, let p = panel {
            hv.rootView = GeminiSecretsFloatingContentView(gemini: gemini, mode: mode, onDismiss: onDismiss)
            p.title = windowTitle(for: mode)
            let contentRect = NSRect(x: 0, y: 0, width: max(p.contentLayoutRect.width, panelWidth), height: contentHeight(for: mode))
            let outer = NSWindow.frameRect(forContentRect: contentRect, styleMask: windowStyle)
            var f = p.frame
            f.size = outer.size
            f = clampFrame(f, to: sc)
            p.setFrame(f, display: true)
            hv.frame = p.contentLayoutRect
            return
        }

        let saved = loadSavedFrame()
        let initial: CGRect
        if let saved {
            let onScreen = dominantScreen(forWindowFrame: saved) ?? sc
            initial = clampFrame(saved, to: onScreen)
        } else {
            initial = defaultFrame(on: sc, mode: mode)
        }

        let panel = GeminiSecretsKeyWindow(
            contentRect: initial,
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )
        panel.title = windowTitle(for: mode)
        panel.level = .normal
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(width: 380, height: 200)
        panel.maxSize = NSSize(width: 900, height: 900)
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let del = GeminiSecretsWindowDelegate()
        del.onWindowWillClose = { [weak self] in
            self?.handleSecretsWindowClosed()
        }
        panel.delegate = del
        windowCloseDelegate = del

        let root = GeminiSecretsFloatingContentView(gemini: gemini, mode: mode, onDismiss: onDismiss)
        let hv = NSHostingView(rootView: root)
        hv.frame = panel.contentLayoutRect
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        let trackedWindowNumber = panel.windowNumber
        removeMoveObserver()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let w = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self.saveFrame(w.frame)
            }
        }
    }
}
