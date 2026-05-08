import AppKit
import Carbon
import Foundation

final class HoldToTalkHotkeyManager: @unchecked Sendable {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var notificationObserver: NSObjectProtocol?
    private var isPressed = false

    init(notificationCenter: NotificationCenter = .default) {
        installEventHandlerIfNeeded()
        registerCurrentShortcut()

        notificationObserver = notificationCenter.addObserver(
            forName: HoldToTalkShortcutStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerCurrentShortcut()
        }
    }

    deinit {
        unregisterShortcut()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HoldToTalkHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            eventTypes.count,
            &eventTypes,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerCurrentShortcut() {
        unregisterShortcut()

        let shortcut = HoldToTalkShortcutStore.load()
        let hotKeyID = EventHotKeyID(signature: fourCharCode("NTCH"), id: 1)
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        isPressed = false
    }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isPressed = false
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &hotKeyID) {
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                $0
            )
        }

        guard status == noErr, hotKeyID.id == 1 else { return noErr }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            guard !isPressed else { return noErr }
            isPressed = true
            onPress?()
        case UInt32(kEventHotKeyReleased):
            guard isPressed else { return noErr }
            isPressed = false
            onRelease?()
        default:
            break
        }

        return noErr
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
