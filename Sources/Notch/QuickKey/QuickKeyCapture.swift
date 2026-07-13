import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickKeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: UInt64
    @Binding var triggerMode: QuickKeyTriggerMode
    /// When true (Key field), a lone modifier is accepted on key-up if no other key was pressed.
    /// Chord capture always matches Send: keyDown with modifiers.
    var allowPureModifiers: Bool = true
    /// When true (Key field), double-tap while recording sets `.double` automatically.
    var detectDoublePress: Bool = false

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
        view.detectDoublePress = detectDoublePress
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
    var detectDoublePress = false

    private static let doubleInterval: CFTimeInterval = 0.38

    private var isRecording = false
    private var localMonitor: Any?
    private var globalMonitor: Any?

    /// Pure-modifier arm: set on flagsChanged down; cleared if a normal key is pressed.
    private var armedPureModifierKeyCode: Int?

    /// First press while detecting double — waiting for a second tap or timeout.
    private var pendingFirst: PendingFirstPress?
    private var pendingTimeout: DispatchWorkItem?

    private struct PendingFirstPress {
        let keyCode: Int
        let modifiers: UInt64
        let isModifier: Bool
        let startedAt: CFAbsoluteTime
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        clearPending(commitAsSingle: false)
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
        clearPending(commitAsSingle: false)
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

    /// Chord capture on non-modifier keyDown (same as Send). Optional double-tap.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            clearPending(commitAsSingle: false)
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

    /// Pure modifiers only for Key: arm on down, commit on up if no key (or double-tap).
    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        guard allowPureModifiers else { return false }

        let code = Int(event.keyCode)
        guard QuickKeyModifier.isPureCaptureKey(code) else { return false }

        if QuickKeyModifier.isDown(keyCode: code, nsFlags: event.modifierFlags) {
            // If already waiting on this pure mod from a prior tap, second down = double.
            if detectDoublePress,
               let pending = pendingFirst,
               pending.isModifier,
               pending.keyCode == code,
               pending.modifiers == 0,
               CFAbsoluteTimeGetCurrent() - pending.startedAt <= Self.doubleInterval {
                clearPending(commitAsSingle: false)
                finishCapture(keyCode: code, modifiers: 0, mode: .double)
                return true
            }
            // Arm only — do not capture yet, so ⌘ then B can still become ⌘B.
            armedPureModifierKeyCode = code
            return false
        }

        // Key-up of the armed pure modifier with no intervening keyDown.
        guard armedPureModifierKeyCode == code else { return false }
        armedPureModifierKeyCode = nil
        return acceptPress(keyCode: code, modifiers: 0, isModifier: true)
    }

    private func acceptPress(keyCode: Int, modifiers: UInt64, isModifier: Bool) -> Bool {
        if !detectDoublePress {
            finishCapture(keyCode: keyCode, modifiers: modifiers, mode: .single)
            return true
        }

        if let pending = pendingFirst,
           pending.keyCode == keyCode,
           pending.modifiers == modifiers,
           pending.isModifier == isModifier,
           CFAbsoluteTimeGetCurrent() - pending.startedAt <= Self.doubleInterval {
            clearPending(commitAsSingle: false)
            finishCapture(keyCode: keyCode, modifiers: modifiers, mode: .double)
            return true
        }

        // First tap — wait briefly for a second tap (double-click style).
        clearPending(commitAsSingle: false)
        pendingFirst = PendingFirstPress(
            keyCode: keyCode,
            modifiers: modifiers,
            isModifier: isModifier,
            startedAt: CFAbsoluteTimeGetCurrent()
        )
        let work = DispatchWorkItem { [weak self] in
            self?.clearPending(commitAsSingle: true)
        }
        pendingTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleInterval, execute: work)
        return true
    }

    private func clearPending(commitAsSingle: Bool) {
        pendingTimeout?.cancel()
        pendingTimeout = nil
        guard let pending = pendingFirst else { return }
        pendingFirst = nil
        if commitAsSingle {
            finishCapture(keyCode: pending.keyCode, modifiers: pending.modifiers, mode: .single)
        }
    }

    private func finishCapture(keyCode: Int, modifiers: UInt64, mode: QuickKeyTriggerMode) {
        DispatchQueue.main.async { self.onCapture?(keyCode, modifiers, mode) }
    }
}
