import Foundation

/// Central place for **Notch Pro** checks (server account + optional dev bypass).
enum NotchProEntitlement {
    /// Set `NOTCH_SKIP_PRO_CHECK=1` in the environment to treat the user as Pro (local testing, CI).
    static var isBypassActive: Bool {
        ProcessInfo.processInfo.environment["NOTCH_SKIP_PRO_CHECK"] == "1"
    }

    /// - Parameter backendPro: Server-reported Pro (e.g. after checkout; `GET /auth/me` → `is_pro`).
    static func isProUser(backendPro: Bool) -> Bool {
        isBypassActive || backendPro
    }
}
