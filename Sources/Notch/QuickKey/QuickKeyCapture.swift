import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickKeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: UInt64
    var allowPureModifiers: Bool = true

    func makeNSView(context: Context) -> QuickKeyCaptureView {
        let view = QuickKeyCaptureView()
        view.allowPureModifiers = allowPureModifiers
        view.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            isRecording = false
        }
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: QuickKeyCaptureView, context: Context) {
        nsView.allowPureModifiers = allowPureModifiers
        nsView.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            isRecording = false
        }
        nsView.onCancel = { isRecording = false }
        nsView.setRecording(isRecording)
    }
}

final class QuickKeyCaptureView: NSView {
    var onCapture: ((Int, UInt64) -> Void)?
    var onCancel: (() -> Void)?
    var allowPureModifiers = true

    private var isRecording = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        if recording { startMonitors() } else { stopMonitors() }
    }

    private func startMonitors() {
        stopMonitors()
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handle(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isRecording else { return }
            _ = self.handle(event)
        }
    }

    private func stopMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown: return handleKeyDown(event)
        case .flagsChanged: return handleFlagsChanged(event)
        default: return false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            DispatchQueue.main.async { self.onCancel?() }
            return true
        }
        let code = Int(event.keyCode)
        if QuickKeyModifier.isModifierKeyCode(code) { return false }
        let mods = QuickKeyChord.modifiers(from: event.modifierFlags)
        DispatchQueue.main.async { self.onCapture?(code, mods) }
        return true
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard allowPureModifiers else { return false }
        let code = Int(event.keyCode)
        guard QuickKeyModifier.isPureCaptureKey(code) else { return false }
        guard QuickKeyModifier.isDown(keyCode: code, nsFlags: event.modifierFlags) else { return false }
        DispatchQueue.main.async { self.onCapture?(code, 0) }
        return true
    }
}
