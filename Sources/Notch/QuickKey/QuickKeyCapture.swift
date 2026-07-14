import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickKeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: UInt64
    @Binding var triggerMode: QuickKeyTriggerMode
    /// When true (Key field), a lone modifier is accepted on key-up if no other key was pressed.
    var allowPureModifiers: Bool = true
    /// When true (Key field), multi-tap while recording sets ×2 / ×3 automatically.
    var detectMultiPress: Bool = false

    func makeNSView(context: Context) -> QuickKeyCaptureView {
        let view = QuickKeyCaptureView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: QuickKeyCaptureView, context: Context) {
        configure(nsView)
        nsView.setRecording(isRecording)
    }

    private func configure(_ view: QuickKeyCaptureView) {
        view.allowPureModifiers = allowPureModifiers
        view.detectMultiPress = detectMultiPress
        view.onCapture = { code, mods, mode in
            keyCode = code
            modifiers = mods
            triggerMode = mode
            isRecording = false
        }
        view.onCancel = { isRecording = false }
    }
}

final class QuickKeyCaptureView: NSView {
    var onCapture: ((Int, UInt64, QuickKeyTriggerMode) -> Void)?
    var onCancel: (() -> Void)?
    var allowPureModifiers = true
    var detectMultiPress = false

    private static let multiInterval: CFTimeInterval = 0.38
    private static let maxPresses = 3

    private var isRecording = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private var armedPureModifierKeyCode: Int?
    private var pending: PendingPress?
    private var pendingTimeout: DispatchWorkItem?

    private struct PendingPress {
        let keyCode: Int
        let modifiers: UInt64
        let isModifier: Bool
        var pressCount: Int
        var lastAt: CFAbsoluteTime
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        clearPending(commit: false)
        armedPureModifierKeyCode = nil
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
        clearPending(commit: false)
        armedPureModifierKeyCode = nil
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
            clearPending(commit: false)
            armedPureModifierKeyCode = nil
            DispatchQueue.main.async { self.onCancel?() }
            return true
        }

        let code = Int(event.keyCode)
        if QuickKeyModifier.isModifierKeyCode(code) {
            return false
        }

        armedPureModifierKeyCode = nil
        let mods = QuickKeyChord.modifiers(from: event.modifierFlags)
        return acceptPress(keyCode: code, modifiers: mods, isModifier: false)
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard allowPureModifiers else { return false }

        let code = Int(event.keyCode)
        guard QuickKeyModifier.isPureCaptureKey(code) else { return false }

        if QuickKeyModifier.isDown(keyCode: code, nsFlags: event.modifierFlags) {
            // Extra downs of the same pure mod count as multi-tap taps.
            if detectMultiPress,
               let pending,
               pending.isModifier,
               pending.keyCode == code,
               pending.modifiers == 0,
               CFAbsoluteTimeGetCurrent() - pending.lastAt <= Self.multiInterval {
                return acceptPress(keyCode: code, modifiers: 0, isModifier: true)
            }
            armedPureModifierKeyCode = code
            return false
        }

        guard armedPureModifierKeyCode == code else { return false }
        armedPureModifierKeyCode = nil
        return acceptPress(keyCode: code, modifiers: 0, isModifier: true)
    }

    private func acceptPress(keyCode: Int, modifiers: UInt64, isModifier: Bool) -> Bool {
        if !detectMultiPress {
            finishCapture(keyCode: keyCode, modifiers: modifiers, mode: .single)
            return true
        }

        let now = CFAbsoluteTimeGetCurrent()
        if var pending,
           pending.keyCode == keyCode,
           pending.modifiers == modifiers,
           pending.isModifier == isModifier,
           now - pending.lastAt <= Self.multiInterval {
            pending.pressCount = min(pending.pressCount + 1, Self.maxPresses)
            pending.lastAt = now
            self.pending = pending
            if pending.pressCount >= Self.maxPresses {
                clearPending(commit: false)
                finishCapture(keyCode: keyCode, modifiers: modifiers, mode: .triple)
                return true
            }
            rescheduleTimeout()
            return true
        }

        // First tap — wait for more taps or timeout → single.
        clearPending(commit: false)
        pending = PendingPress(
            keyCode: keyCode,
            modifiers: modifiers,
            isModifier: isModifier,
            pressCount: 1,
            lastAt: now
        )
        rescheduleTimeout()
        return true
    }

    private func rescheduleTimeout() {
        pendingTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.clearPending(commit: true)
        }
        pendingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.multiInterval, execute: work)
    }

    private func clearPending(commit: Bool) {
        pendingTimeout?.cancel()
        pendingTimeout = nil
        guard let pending else { return }
        self.pending = nil
        if commit {
            let mode = QuickKeyTriggerMode(pressCount: pending.pressCount)
            finishCapture(keyCode: pending.keyCode, modifiers: pending.modifiers, mode: mode)
        }
    }

    private func finishCapture(keyCode: Int, modifiers: UInt64, mode: QuickKeyTriggerMode) {
        DispatchQueue.main.async { self.onCapture?(keyCode, modifiers, mode) }
    }
}
