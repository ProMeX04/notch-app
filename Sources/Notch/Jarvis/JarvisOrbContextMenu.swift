import AppKit
import Foundation

private enum JarvisOrbMenuTags {
    static let toggleAlwaysOnTop = 100
    static let toggleDock = 101
    static let openTalkSettings = 102
    static let orbStylePrefix = 1_000
}

private enum JarvisOrbParsedMenuSelection {
    case toggleAlwaysOnTop
    case toggleDock
    case openTalkSettings
    case selectStyle(Int)
    case unrecognized

    init(tag: Int) {
        switch tag {
        case JarvisOrbMenuTags.toggleAlwaysOnTop: self = .toggleAlwaysOnTop
        case JarvisOrbMenuTags.toggleDock: self = .toggleDock
        case JarvisOrbMenuTags.openTalkSettings: self = .openTalkSettings
        default:
            if tag >= JarvisOrbMenuTags.orbStylePrefix {
                self = .selectStyle(tag - JarvisOrbMenuTags.orbStylePrefix)
            } else {
                self = .unrecognized
            }
        }
    }
}

/// `NSMenuItem` cần `target` là NSObject subclass.
@MainActor
final class JarvisOrbContextMenuActions: NSObject {
    static let shared = JarvisOrbContextMenuActions()

    private override init() {
        super.init()
    }

    @objc(handleOrbMenuSelection:)
    func handleOrbMenuSelection(_ sender: NSMenuItem) {
        handleOrbMenuSelectionOnMain(sender)
    }

    private func handleOrbMenuSelectionOnMain(_ sender: NSMenuItem) {
        let parsed = JarvisOrbParsedMenuSelection(tag: sender.tag)

        switch parsed {
        case .toggleAlwaysOnTop:
            UserDefaults.standard.set(
                !JarvisTalkBackgroundOrbSettings.prefersOrbAboveNormalWindows,
                forKey: JarvisTalkBackgroundOrbSettings.alwaysOnTopUserDefaultsKey
            )
        case .toggleDock:
            UserDefaults.standard.set(
                !JarvisTalkBackgroundOrbSettings.prefersDockIconWhileOrbShown,
                forKey: JarvisTalkBackgroundOrbSettings.showInDockWhenOrbVisibleDefaultsKey
            )
        case .openTalkSettings:
            AppSettingsController.shared.open(tab: .talk)
        case let .selectStyle(index):
            let styles = JarvisOrbVisualStyle.allCases
            guard styles.indices.contains(index) else { return }
            UserDefaults.standard.set(styles[index].rawValue, forKey: JarvisOrbVisualStyle.storageKey)
            JarvisBackgroundWindowController.shared.reloadOrbEmbeddedWebIfStoredPresetChanged()
        case .unrecognized:
            break
        }

        JarvisBackgroundWindowController.shared.refreshOrbPresentationFromDefaults()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }
}

@MainActor
enum JarvisOrbContextMenu {
    private static var appLanguage: String {
        if let raw = UserDefaults.standard.string(forKey: "app_language"), !raw.isEmpty {
            return raw
        }
        return "English"
    }

    static func makeOrbMenu() -> NSMenu {
        let lang = Self.appLanguage
        let root = NSMenu(title: Localization.get("Orb menu", lang: lang))

        let styleSubmenu = NSMenu(title: Localization.get("Orb appearance", lang: lang))
        let storedRaw = JarvisOrbVisualStyle.stored.rawValue
        for (index, style) in JarvisOrbVisualStyle.allCases.enumerated() {
            let row = menuItemRow(
                text: OrbStyleTitles.localized(style: style, lang: lang),
                checked: style.rawValue == storedRaw,
                tag: JarvisOrbMenuTags.orbStylePrefix + index
            )
            styleSubmenu.addItem(row)
        }
        let appearanceItem = NSMenuItem(title: Localization.get("Orb appearance", lang: lang), action: nil, keyEquivalent: "")
        appearanceItem.submenu = styleSubmenu
        root.addItem(appearanceItem)

        root.addItem(
            menuItemRow(
                text: Localization.get("Orb always on top", lang: lang),
                checked: JarvisTalkBackgroundOrbSettings.prefersOrbAboveNormalWindows,
                tag: JarvisOrbMenuTags.toggleAlwaysOnTop
            ))

        root.addItem(
            menuItemRow(
                text: Localization.get("Orb menu Show in Dock", lang: lang),
                checked: JarvisTalkBackgroundOrbSettings.prefersDockIconWhileOrbShown,
                tag: JarvisOrbMenuTags.toggleDock
            ))

        root.addItem(.separator())

        root.addItem(
            actionItem(
                title: Localization.get("Orb menu Open Talk settings", lang: lang),
                tag: JarvisOrbMenuTags.openTalkSettings
            ))

        return root
    }

    private static func actionItem(title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(JarvisOrbContextMenuActions.handleOrbMenuSelection(_:)),
            keyEquivalent: ""
        )
        item.tag = tag
        item.target = JarvisOrbContextMenuActions.shared
        return item
    }

    private static func menuItemRow(text: String, checked: Bool, tag: Int) -> NSMenuItem {
        let titleTxt = checked ? ("✓ " + text) : text
        return actionItem(title: titleTxt, tag: tag)
    }

    private enum OrbStyleTitles {
        static func localized(style: JarvisOrbVisualStyle, lang: String) -> String {
            switch style {
            case .ice: Localization.get("Orb style Ice", lang: lang)
            case .ember: Localization.get("Orb style Ember", lang: lang)
            case .nebula: Localization.get("Orb style Nebula", lang: lang)
            case .aurora: Localization.get("Orb style Aurora", lang: lang)
            case .mono: Localization.get("Orb style Mono", lang: lang)
            case .particleWave: Localization.get("Orb style Particle Wave", lang: lang)
            }
        }
    }
}
