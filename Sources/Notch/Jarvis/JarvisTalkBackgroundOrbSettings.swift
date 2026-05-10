import Foundation

/// User preference cho cửa sổ orb nổi khi Gemini Live có phiên đang hiển thị.
enum JarvisTalkBackgroundOrbSettings {
    static let enabledUserDefaultsKey = "jarvisTalkBackgroundOrbEffectEnabled"
    /// Khi `true`, orb dùng `NotchHUDWindowLevels` vừa trên cửa sổ tài liệu app khác,
    /// vẫn thấp hơn `NSWindow.Level.floating` (caption Gemini, panel HUD Notch nhẹ).
    static let alwaysOnTopUserDefaultsKey = "jarvisOrbAlwaysOnTopEnabled"
    /// Khi có cửa sổ orb, chuyển `NSApplication` sang `.regular` để icon Notch hiện trong Dock (LSUIElement vẫn có thể gây khác biệt tùy hệ).
    static let showInDockWhenOrbVisibleDefaultsKey = "jarvisOrbShowInDockWhenOrbVisibleEnabled"

    /// Default `true`: matches prior behavior until the user turns it off explicitly.
    static var isEffectEnabled: Bool {
        guard UserDefaults.standard.object(forKey: enabledUserDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledUserDefaultsKey)
    }

    static var prefersOrbAboveNormalWindows: Bool {
        guard UserDefaults.standard.object(forKey: alwaysOnTopUserDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: alwaysOnTopUserDefaultsKey)
    }

    /// Hiện app trong Dock khi có cửa sổ orb (phiên Talk đủ điều kiện).
    static var prefersDockIconWhileOrbShown: Bool {
        guard UserDefaults.standard.object(forKey: showInDockWhenOrbVisibleDefaultsKey) != nil else {
            return false
        }
        return UserDefaults.standard.bool(forKey: showInDockWhenOrbVisibleDefaultsKey)
    }
}
