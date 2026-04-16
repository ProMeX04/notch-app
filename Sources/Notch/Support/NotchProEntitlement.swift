import Foundation

/// Central place for **Notch Pro** checks (StoreKit, server account, optional dev bypass).
enum NotchProEntitlement {
    /// Set `NOTCH_SKIP_PRO_CHECK=1` in the environment to treat the user as Pro (local testing, CI).
    static var isBypassActive: Bool {
        ProcessInfo.processInfo.environment["NOTCH_SKIP_PRO_CHECK"] == "1"
    }

    /// - Parameters:
    ///   - storeKitEntitled: Active Mac App Store subscription (StoreKit 2).
    ///   - backendPro: Server-reported Pro (e.g. after web checkout; `GET /auth/me` → `is_pro`).
    static func isProUser(storeKitEntitled: Bool, backendPro: Bool) -> Bool {
        isBypassActive || storeKitEntitled || backendPro
    }
}
