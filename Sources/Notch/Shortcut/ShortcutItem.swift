import Foundation

enum ShortcutAction: Codable, Equatable, Sendable {
    /// Universal: any URL macOS can open (web, deep link, file, shortcuts://, etc.)
    case openURL(String)
    /// Launch app by bundle identifier (convenience, uses NSWorkspace.launchApp)
    case launchApp(bundleID: String)
    /// Run AppleScript source code
    case appleScript(source: String)
    /// Run shell command (requires approval gate)
    case shellCommand(String)
    /// Future-proof: plugin type + JSON-like config
    case plugin(type: String, config: [String: String])
}

struct ShortcutItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var imagePath: String?
    var tintColor: String
    var action: ShortcutAction
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "star",
        imagePath: String? = nil,
        tintColor: String = "blue",
        action: ShortcutAction,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.imagePath = imagePath
        self.tintColor = tintColor
        self.action = action
        self.sortOrder = sortOrder
    }
}

// MARK: - Convenience init from open URL

extension ShortcutItem {
    static func openURL(name: String, url: String, icon: String = "globe", tintColor: String = "blue") -> ShortcutItem {
        ShortcutItem(name: name, icon: icon, tintColor: tintColor, action: .openURL(url))
    }

    static func launchApp(name: String, bundleID: String, icon: String = "app", tintColor: String = "purple") -> ShortcutItem {
        ShortcutItem(name: name, icon: icon, tintColor: tintColor, action: .launchApp(bundleID: bundleID))
    }

    static func appleScript(name: String, source: String, icon: String = "applescript", tintColor: String = "orange") -> ShortcutItem {
        ShortcutItem(name: name, icon: icon, tintColor: tintColor, action: .appleScript(source: source))
    }

    static func shellCommand(name: String, command: String, icon: String = "terminal", tintColor: String = "green") -> ShortcutItem {
        ShortcutItem(name: name, icon: icon, tintColor: tintColor, action: .shellCommand(command))
    }
}

// MARK: - Action display info

extension ShortcutAction {
    var typeName: String {
        switch self {
        case .openURL: return "Open URL"
        case .launchApp: return "Launch App"
        case .appleScript: return "AppleScript"
        case .shellCommand: return "Shell Command"
        case .plugin: return "Plugin"
        }
    }

    var icon: String {
        switch self {
        case .openURL: return "globe"
        case .launchApp: return "app"
        case .appleScript: return "applescript"
        case .shellCommand: return "terminal"
        case .plugin: return "puzzlepiece"
        }
    }

    var requiresApproval: Bool {
        switch self {
        case .openURL, .launchApp:
            return false
        case .appleScript, .shellCommand, .plugin:
            return true
        }
    }

    var previewText: String {
        switch self {
        case .openURL(let url): return url
        case .launchApp(let bundleID): return bundleID
        case .appleScript(let source): return source.prefix(80) + (source.count > 80 ? "…" : "")
        case .shellCommand(let cmd): return cmd
        case .plugin(let type, _): return type
        }
    }
}

// MARK: - Tint color resolution

extension ShortcutItem {
    var resolvedColor: String {
        tintColor
    }

    var normalizedImagePath: String? {
        guard let imagePath else { return nil }
        let trimmed = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
