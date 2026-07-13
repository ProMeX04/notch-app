import Carbon.HIToolbox
import Foundation

enum QuickKeyShortcutParser {
    struct Result: Equatable {
        var keyCode: Int
        var modifiers: UInt64
    }

    enum ParseError: LocalizedError {
        case empty
        case unknownToken(String)
        case missingKey
        case multipleKeys

        var errorDescription: String? {
            switch self {
            case .empty: return "Empty"
            case .unknownToken(let t): return "Unknown: \(t)"
            case .missingKey: return "Missing key"
            case .multipleKeys: return "Only one main key"
            }
        }
    }

    static func parse(_ raw: String) -> Swift.Result<Result, ParseError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        var s = trimmed
        s = s.replacingOccurrences(of: "⌘", with: " cmd ")
        s = s.replacingOccurrences(of: "⌃", with: " ctrl ")
        s = s.replacingOccurrences(of: "⌥", with: " opt ")
        s = s.replacingOccurrences(of: "⇧", with: " shift ")

        let parts = s
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "+ \t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tokens = mergeSideTokens(parts)
        var modifiers: UInt64 = 0
        var resolvedKey: Int?
        var sawKey = false

        for token in tokens {
            if let sideKey = sideModifierKeyCode(token) {
                if sawKey { return .failure(.multipleKeys) }
                resolvedKey = sideKey
                sawKey = true
                continue
            }
            if let flag = chordModifierFlag(token) {
                modifiers |= flag
                continue
            }
            if let code = resolveKeyCode(token) {
                if sawKey { return .failure(.multipleKeys) }
                resolvedKey = code
                sawKey = true
                continue
            }
            return .failure(.unknownToken(token))
        }

        guard let key = resolvedKey else { return .failure(.missingKey) }
        if QuickKeyModifier.isModifierKeyCode(key) {
            return .success(Result(keyCode: key, modifiers: 0))
        }
        return .success(Result(keyCode: key, modifiers: modifiers))
    }

    static func format(keyCode: Int, modifiers: UInt64) -> String {
        if QuickKeyModifier.isModifierKeyCode(keyCode) {
            return formatKeyOnly(keyCode)
        }
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        parts.append(formatKeyOnly(keyCode))
        return parts.joined(separator: "+")
    }

    static func apply(text: String, keyCode: inout Int, modifiers: inout UInt64) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Empty keybinding" }
        switch parse(trimmed) {
        case .success(let r):
            keyCode = r.keyCode
            modifiers = r.modifiers
            return nil
        case .failure(let e):
            return e.errorDescription
        }
    }

    // MARK: - Private

    private static func mergeSideTokens(_ parts: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        let sides: Set = ["right", "left", "r", "l", "phai", "phải", "trai", "trái"]
        while i < parts.count {
            let p = parts[i]
            let folded = p.folding(options: .diacriticInsensitive, locale: .current)
            if sides.contains(p) || sides.contains(folded), i + 1 < parts.count {
                out.append(folded + parts[i + 1])
                i += 2
            } else {
                out.append(p)
                i += 1
            }
        }
        return out
    }

    private static func normalize(_ token: String) -> String {
        token.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private static func sideModifierKeyCode(_ token: String) -> Int? {
        switch normalize(token) {
        case "rcmd", "rcommand", "rightcmd", "rightcommand", "cmdphai", "commandphai":
            return Int(kVK_RightCommand)
        case "lcmd", "lcommand", "leftcmd", "leftcommand", "cmdtrai", "commandtrai":
            return Int(kVK_Command)
        case "rctrl", "rcontrol", "rightctrl", "rightcontrol", "ctrlphai", "controlphai":
            return Int(kVK_RightControl)
        case "lctrl", "lcontrol", "leftctrl", "leftcontrol", "ctrltrai", "controltrai":
            return Int(kVK_Control)
        case "ropt", "roption", "ralt", "rightopt", "rightoption", "rightalt", "optphai", "optionphai", "altphai":
            return Int(kVK_RightOption)
        case "lopt", "loption", "lalt", "leftopt", "leftoption", "leftalt":
            return Int(kVK_Option)
        case "rshift", "rightshift", "shiftphai":
            return Int(kVK_RightShift)
        case "lshift", "leftshift", "shifttrai":
            return Int(kVK_Shift)
        case "fn", "function":
            return Int(kVK_Function)
        case "caps", "capslock":
            return Int(kVK_CapsLock)
        default:
            return nil
        }
    }

    private static func chordModifierFlag(_ token: String) -> UInt64? {
        switch normalize(token) {
        case "cmd", "command", "meta", "super", "win":
            return CGEventFlags.maskCommand.rawValue
        case "ctrl", "control", "ctl":
            return CGEventFlags.maskControl.rawValue
        case "opt", "option", "alt":
            return CGEventFlags.maskAlternate.rawValue
        case "shift", "shft":
            return CGEventFlags.maskShift.rawValue
        default:
            return nil
        }
    }

    private static func resolveKeyCode(_ token: String) -> Int? {
        let t = normalize(token)
        if t.count == 1, let ch = t.first {
            if ch.isLetter {
                let map: [Character: Int] = [
                    "a": Int(kVK_ANSI_A), "b": Int(kVK_ANSI_B), "c": Int(kVK_ANSI_C),
                    "d": Int(kVK_ANSI_D), "e": Int(kVK_ANSI_E), "f": Int(kVK_ANSI_F),
                    "g": Int(kVK_ANSI_G), "h": Int(kVK_ANSI_H), "i": Int(kVK_ANSI_I),
                    "j": Int(kVK_ANSI_J), "k": Int(kVK_ANSI_K), "l": Int(kVK_ANSI_L),
                    "m": Int(kVK_ANSI_M), "n": Int(kVK_ANSI_N), "o": Int(kVK_ANSI_O),
                    "p": Int(kVK_ANSI_P), "q": Int(kVK_ANSI_Q), "r": Int(kVK_ANSI_R),
                    "s": Int(kVK_ANSI_S), "t": Int(kVK_ANSI_T), "u": Int(kVK_ANSI_U),
                    "v": Int(kVK_ANSI_V), "w": Int(kVK_ANSI_W), "x": Int(kVK_ANSI_X),
                    "y": Int(kVK_ANSI_Y), "z": Int(kVK_ANSI_Z),
                ]
                return map[ch]
            }
            if ch.isNumber {
                let map: [Character: Int] = [
                    "0": Int(kVK_ANSI_0), "1": Int(kVK_ANSI_1), "2": Int(kVK_ANSI_2),
                    "3": Int(kVK_ANSI_3), "4": Int(kVK_ANSI_4), "5": Int(kVK_ANSI_5),
                    "6": Int(kVK_ANSI_6), "7": Int(kVK_ANSI_7), "8": Int(kVK_ANSI_8),
                    "9": Int(kVK_ANSI_9),
                ]
                return map[ch]
            }
        }
        if t.hasPrefix("f"), t.count >= 2, t.count <= 3,
           let n = Int(t.dropFirst()), (1...20).contains(n) {
            let codes: [Int: Int] = [
                1: Int(kVK_F1), 2: Int(kVK_F2), 3: Int(kVK_F3), 4: Int(kVK_F4),
                5: Int(kVK_F5), 6: Int(kVK_F6), 7: Int(kVK_F7), 8: Int(kVK_F8),
                9: Int(kVK_F9), 10: Int(kVK_F10), 11: Int(kVK_F11), 12: Int(kVK_F12),
                13: Int(kVK_F13), 14: Int(kVK_F14), 15: Int(kVK_F15), 16: Int(kVK_F16),
                17: Int(kVK_F17), 18: Int(kVK_F18), 19: Int(kVK_F19), 20: Int(kVK_F20),
            ]
            return codes[n]
        }
        switch t {
        case "space", "spc": return Int(kVK_Space)
        case "return", "enter", "ret": return Int(kVK_Return)
        case "tab": return Int(kVK_Tab)
        case "esc", "escape": return Int(kVK_Escape)
        case "delete", "backspace", "bs": return Int(kVK_Delete)
        case "fwddelete", "forwarddelete", "del": return Int(kVK_ForwardDelete)
        case "left", "leftarrow": return Int(kVK_LeftArrow)
        case "right", "rightarrow": return Int(kVK_RightArrow)
        case "up", "uparrow": return Int(kVK_UpArrow)
        case "down", "downarrow": return Int(kVK_DownArrow)
        case "home": return Int(kVK_Home)
        case "end": return Int(kVK_End)
        case "pageup", "pgup": return Int(kVK_PageUp)
        case "pagedown", "pgdn", "pgdown": return Int(kVK_PageDown)
        case "help", "insert", "ins": return Int(kVK_Help)
        // PC Menu / Application key (virtual key 110 / 0x6E)
        case "menu", "contextmenu", "ctxmenu", "appmenu", "contextualmenu":
            return Int(kVK_ContextualMenu)
        case "volup", "volumeup": return Int(kVK_VolumeUp)
        case "voldown", "volumedown": return Int(kVK_VolumeDown)
        case "mute": return Int(kVK_Mute)
        default:
            // Round-trip unknown hardware keys: key110, vk110, (110), or bare multi-digit
            if t.hasPrefix("key"), let n = Int(t.dropFirst(3)), (0...255).contains(n) {
                return n
            }
            if t.hasPrefix("vk"), let n = Int(t.dropFirst(2)), (0...255).contains(n) {
                return n
            }
            // Strip parentheses from format "(110)" legacy
            if t.hasPrefix("("), t.hasSuffix(")"), t.count > 2,
               let n = Int(t.dropFirst().dropLast()), (0...255).contains(n) {
                return n
            }
            // Multi-digit number = raw key code (single 0–9 already handled as ANSI digits)
            if t.count >= 2, let n = Int(t), (0...255).contains(n) {
                return n
            }
            return nil
        }
    }

    private static func formatKeyOnly(_ keyCode: Int) -> String {
        switch keyCode {
        case Int(kVK_RightCommand): return "rcmd"
        case Int(kVK_Command): return "lcmd"
        case Int(kVK_RightControl): return "rctrl"
        case Int(kVK_Control): return "lctrl"
        case Int(kVK_RightOption): return "ropt"
        case Int(kVK_Option): return "lopt"
        case Int(kVK_RightShift): return "rshift"
        case Int(kVK_Shift): return "lshift"
        case Int(kVK_Function): return "fn"
        case Int(kVK_CapsLock): return "caps"
        case Int(kVK_Space): return "space"
        case Int(kVK_Return): return "enter"
        case Int(kVK_Tab): return "tab"
        case Int(kVK_Escape): return "esc"
        case Int(kVK_Delete): return "delete"
        case Int(kVK_ContextualMenu): return "menu"
        case Int(kVK_VolumeUp): return "volup"
        case Int(kVK_VolumeDown): return "voldown"
        case Int(kVK_Mute): return "mute"
        case Int(kVK_F1): return "f1"
        case Int(kVK_F2): return "f2"
        case Int(kVK_F3): return "f3"
        case Int(kVK_F4): return "f4"
        case Int(kVK_F5): return "f5"
        case Int(kVK_F6): return "f6"
        case Int(kVK_F7): return "f7"
        case Int(kVK_F8): return "f8"
        case Int(kVK_F9): return "f9"
        case Int(kVK_F10): return "f10"
        case Int(kVK_F11): return "f11"
        case Int(kVK_F12): return "f12"
        case Int(kVK_F13): return "f13"
        case Int(kVK_F14): return "f14"
        case Int(kVK_F15): return "f15"
        case Int(kVK_F16): return "f16"
        case Int(kVK_F17): return "f17"
        case Int(kVK_F18): return "f18"
        case Int(kVK_F19): return "f19"
        case Int(kVK_F20): return "f20"
        default:
            let name = QuickKeyChord.keyName(for: keyCode)
            if name.count == 1 { return name.lowercased() }
            // Stable round-trip for hardware keys we don't name
            if name.hasPrefix("Key") { return "key\(keyCode)" }
            return name.lowercased()
        }
    }
}
