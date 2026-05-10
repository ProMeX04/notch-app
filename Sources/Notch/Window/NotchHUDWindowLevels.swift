import AppKit

/// Thứ tự xếp lớp HUD Notch và orb Gemini (đáy → trên trong cùng Space).
///
/// - Orb nằm **trên** cửa sổ tài liệu thông thường (`.normal`).
/// - Orb nằm **dưới** các panel Gemini dùng `NSWindow.Level.floating` (caption talk, banner nhẹ …).
/// - Phê duyệt/exec, transcript overlay v.v. dùng `aboveOrb`.
enum NotchHUDWindowLevels {

    /// Cao hơn app bên thứ ba nhưng thấp hơn một bậc `.floating` — chỗ Notch HUD “nhẹ”.
    /// Dù đặt Gemini panels ở `.floating`, orb sẽ không che caption / ô nhập.
    static let orbOverExternalAppsBelowNotchFloaterTier: NSWindow.Level = NSWindow.Level.floating - 1

    /// Cao hơn orb và thường cả tier `.floating` — khi HUD *bắt buộc* luôn nổi.
    static let aboveOrb: NSWindow.Level = NSWindow.Level.floating + 2
}
