import ApplicationServices
import AppKit
import Combine

@MainActor
final class QuickKeyAccessibility: ObservableObject {
    static let shared = QuickKeyAccessibility()

    @Published private(set) var isTrusted: Bool = false

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAndSyncEngine()
            }
        }
    }

    @discardableResult
    func refresh() -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
        return trusted
    }

    func refreshAndSyncEngine() {
        let was = isTrusted
        let now = refresh()
        if now && !was {
            QuickKeyEngine.shared.start()
        } else if !now && was {
            QuickKeyEngine.shared.stop()
        } else if now {
            QuickKeyEngine.shared.restartIfNeeded()
        }
    }

    func request() {
        // String key avoids Swift 6 shared-mutable CFString concurrency diagnostic.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAndSyncEngine()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
