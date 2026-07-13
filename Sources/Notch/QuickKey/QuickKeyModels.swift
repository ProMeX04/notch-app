import AppKit
import Carbon.HIToolbox
import Foundation

/// How many times the trigger key must be pressed to fire the mapping.
enum QuickKeyTriggerMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case single
    case double

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        }
    }

    var shortBadge: String {
        switch self {
        case .single: return ""
        case .double: return "×2"
        }
    }
}

/// Spare key → app shortcut (optional frontmost-app scope).
struct QuickKeyMapping: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var triggerKeyCode: Int
    var triggerModifiers: UInt64
    /// `.single` = one press; `.double` = two presses within a short window.
    var triggerMode: QuickKeyTriggerMode
    var targetKeyCode: Int
    var targetModifiers: UInt64
    var appBundleID: String?
    var appDisplayName: String?

    init(
        id: UUID = UUID(),
        name: String = "Shortcut",
        isEnabled: Bool = true,
        triggerKeyCode: Int = Int(kVK_RightCommand),
        triggerModifiers: UInt64 = 0,
        triggerMode: QuickKeyTriggerMode = .single,
        targetKeyCode: Int = Int(kVK_ANSI_B),
        targetModifiers: UInt64 = CGEventFlags.maskCommand.rawValue,
        appBundleID: String? = nil,
        appDisplayName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.triggerKeyCode = triggerKeyCode
        self.triggerModifiers = triggerModifiers
        self.triggerMode = triggerMode
        self.targetKeyCode = targetKeyCode
        self.targetModifiers = targetModifiers
        self.appBundleID = appBundleID
        self.appDisplayName = appDisplayName
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled
        case triggerKeyCode, triggerModifiers, triggerMode
        case targetKeyCode, targetModifiers
        case appBundleID, appDisplayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        triggerKeyCode = try c.decode(Int.self, forKey: .triggerKeyCode)
        triggerModifiers = try c.decode(UInt64.self, forKey: .triggerModifiers)
        triggerMode = try c.decodeIfPresent(QuickKeyTriggerMode.self, forKey: .triggerMode) ?? .single
        targetKeyCode = try c.decode(Int.self, forKey: .targetKeyCode)
        targetModifiers = try c.decode(UInt64.self, forKey: .targetModifiers)
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        appDisplayName = try c.decodeIfPresent(String.self, forKey: .appDisplayName)
    }

    var triggerDisplay: String {
        let base = QuickKeyChord.display(keyCode: triggerKeyCode, modifiers: triggerModifiers)
        switch triggerMode {
        case .single:
            return base
        case .double:
            return "\(base) ×2"
        }
    }

    var targetDisplay: String {
        QuickKeyChord.display(keyCode: targetKeyCode, modifiers: targetModifiers)
    }

    var whenDisplay: String {
        if let appDisplayName, !appDisplayName.isEmpty { return appDisplayName }
        if let appBundleID, !appBundleID.isEmpty { return appBundleID }
        return "Always"
    }
}

enum QuickKeyChord {
    static let relevantModifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue

    static func display(keyCode: Int, modifiers: UInt64) -> String {
        if QuickKeyModifier.isModifierKeyCode(keyCode) {
            return keyName(for: keyCode)
        }
        var s = ""
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            Int(kVK_ANSI_A): "A", Int(kVK_ANSI_B): "B", Int(kVK_ANSI_C): "C",
            Int(kVK_ANSI_D): "D", Int(kVK_ANSI_E): "E", Int(kVK_ANSI_F): "F",
            Int(kVK_ANSI_G): "G", Int(kVK_ANSI_H): "H", Int(kVK_ANSI_I): "I",
            Int(kVK_ANSI_J): "J", Int(kVK_ANSI_K): "K", Int(kVK_ANSI_L): "L",
            Int(kVK_ANSI_M): "M", Int(kVK_ANSI_N): "N", Int(kVK_ANSI_O): "O",
            Int(kVK_ANSI_P): "P", Int(kVK_ANSI_Q): "Q", Int(kVK_ANSI_R): "R",
            Int(kVK_ANSI_S): "S", Int(kVK_ANSI_T): "T", Int(kVK_ANSI_U): "U",
            Int(kVK_ANSI_V): "V", Int(kVK_ANSI_W): "W", Int(kVK_ANSI_X): "X",
            Int(kVK_ANSI_Y): "Y", Int(kVK_ANSI_Z): "Z",
            Int(kVK_ANSI_0): "0", Int(kVK_ANSI_1): "1", Int(kVK_ANSI_2): "2",
            Int(kVK_ANSI_3): "3", Int(kVK_ANSI_4): "4", Int(kVK_ANSI_5): "5",
            Int(kVK_ANSI_6): "6", Int(kVK_ANSI_7): "7", Int(kVK_ANSI_8): "8",
            Int(kVK_ANSI_9): "9",
            Int(kVK_ANSI_Equal): "=", Int(kVK_ANSI_Minus): "-",
            Int(kVK_ANSI_RightBracket): "]", Int(kVK_ANSI_LeftBracket): "[",
            Int(kVK_ANSI_Quote): "'", Int(kVK_ANSI_Semicolon): ";",
            Int(kVK_ANSI_Backslash): "\\", Int(kVK_ANSI_Comma): ",",
            Int(kVK_ANSI_Slash): "/", Int(kVK_ANSI_Period): ".",
            Int(kVK_ANSI_Grave): "`",
            Int(kVK_Return): "↵", Int(kVK_Tab): "⇥", Int(kVK_Space): "Space",
            Int(kVK_Delete): "⌫", Int(kVK_Escape): "Esc",
            Int(kVK_Command): "l⌘", Int(kVK_Shift): "l⇧",
            Int(kVK_CapsLock): "Caps", Int(kVK_Option): "l⌥",
            Int(kVK_Control): "l⌃",
            Int(kVK_RightCommand): "r⌘", Int(kVK_RightShift): "r⇧",
            Int(kVK_RightOption): "r⌥", Int(kVK_RightControl): "r⌃",
            Int(kVK_Function): "Fn",
            Int(kVK_F1): "F1", Int(kVK_F2): "F2", Int(kVK_F3): "F3",
            Int(kVK_F4): "F4", Int(kVK_F5): "F5", Int(kVK_F6): "F6",
            Int(kVK_F7): "F7", Int(kVK_F8): "F8", Int(kVK_F9): "F9",
            Int(kVK_F10): "F10", Int(kVK_F11): "F11", Int(kVK_F12): "F12",
            Int(kVK_F13): "F13", Int(kVK_F14): "F14", Int(kVK_F15): "F15",
            Int(kVK_F16): "F16", Int(kVK_F17): "F17", Int(kVK_F18): "F18",
            Int(kVK_F19): "F19", Int(kVK_F20): "F20",
            Int(kVK_LeftArrow): "←", Int(kVK_RightArrow): "→",
            Int(kVK_DownArrow): "↓", Int(kVK_UpArrow): "↑",
            Int(kVK_Home): "Home", Int(kVK_End): "End",
            Int(kVK_PageUp): "PgUp", Int(kVK_PageDown): "PgDn",
            Int(kVK_ForwardDelete): "⌦", Int(kVK_Help): "Ins",
            // PC keyboards: Menu / Application key (0x6E = 110)
            Int(kVK_ContextualMenu): "Menu",
            Int(kVK_VolumeUp): "Vol+", Int(kVK_VolumeDown): "Vol-",
            Int(kVK_Mute): "Mute",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    static func modifiers(from eventFlags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if eventFlags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        if eventFlags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        if eventFlags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        if eventFlags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        return result
    }
}

enum QuickKeyModifier {
    static func isModifierKeyCode(_ keyCode: Int) -> Bool {
        switch keyCode {
        case Int(kVK_Command), Int(kVK_Shift), Int(kVK_CapsLock),
             Int(kVK_Option), Int(kVK_Control), Int(kVK_RightCommand),
             Int(kVK_RightShift), Int(kVK_RightOption), Int(kVK_RightControl),
             Int(kVK_Function):
            return true
        default:
            return false
        }
    }

    static func isDown(keyCode: Int, nsFlags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case Int(kVK_Shift), Int(kVK_RightShift): return nsFlags.contains(.shift)
        case Int(kVK_Command), Int(kVK_RightCommand): return nsFlags.contains(.command)
        case Int(kVK_Option), Int(kVK_RightOption): return nsFlags.contains(.option)
        case Int(kVK_Control), Int(kVK_RightControl): return nsFlags.contains(.control)
        case Int(kVK_CapsLock): return nsFlags.contains(.capsLock)
        case Int(kVK_Function): return nsFlags.contains(.function)
        default: return false
        }
    }

    static func isDown(keyCode: Int, cgFlags: CGEventFlags) -> Bool {
        switch keyCode {
        case Int(kVK_Shift), Int(kVK_RightShift): return cgFlags.contains(.maskShift)
        case Int(kVK_Command), Int(kVK_RightCommand): return cgFlags.contains(.maskCommand)
        case Int(kVK_Option), Int(kVK_RightOption): return cgFlags.contains(.maskAlternate)
        case Int(kVK_Control), Int(kVK_RightControl): return cgFlags.contains(.maskControl)
        case Int(kVK_CapsLock): return cgFlags.contains(.maskAlphaShift)
        case Int(kVK_Function): return cgFlags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    static func isPureCaptureKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case Int(kVK_RightCommand), Int(kVK_RightControl),
             Int(kVK_RightOption), Int(kVK_RightShift),
             Int(kVK_Function):
            return true
        default:
            return false
        }
    }

    static func flag(for keyCode: Int) -> CGEventFlags {
        switch keyCode {
        case Int(kVK_Shift), Int(kVK_RightShift): return .maskShift
        case Int(kVK_Command), Int(kVK_RightCommand): return .maskCommand
        case Int(kVK_Option), Int(kVK_RightOption): return .maskAlternate
        case Int(kVK_Control), Int(kVK_RightControl): return .maskControl
        case Int(kVK_Function): return .maskSecondaryFn
        case Int(kVK_CapsLock): return .maskAlphaShift
        default: return []
        }
    }
}

extension Notification.Name {
    static let quickKeyMappingsDidChange = Notification.Name("notch.quickKey.mappingsDidChange")
}
