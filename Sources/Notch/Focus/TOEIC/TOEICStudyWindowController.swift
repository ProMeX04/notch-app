import AppKit
import SwiftUI

// Uses SwiftUI `Color` for accent wiring into the study root view.

@MainActor
final class TOEICStudyWindowController {
    static let shared = TOEICStudyWindowController()

    private var window: NSWindow?

    private init() {}

    func show(tint: Color? = nil) {
        let resolvedTint = tint ?? NotchAccentColorOption.resolve(
            rawValue: UserDefaults.standard.string(forKey: NotchAccentColorOption.storageKey)
                ?? NotchAccentColorOption.defaultOption.rawValue
        ).brightColor

        if window == nil {
            let root = TOEICStudyRootView(tint: resolvedTint)
                .frame(minWidth: 440, minHeight: 520)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "TOEIC"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 480, height: 580))
            win.isReleasedWhenClosed = false
            win.backgroundColor = NSColor.black
            win.titlebarAppearsTransparent = true
            win.appearance = NSAppearance(named: .darkAqua)
            win.hidesOnDeactivate = false
            applyAlwaysOnTop(win)
            window = win
        }

        TOEICStudyViewModel.shared.progress.load()
        TOEICStudyViewModel.shared.reloadBank()

        guard let window else { return }
        applyAlwaysOnTop(window)
        if !window.isVisible {
            window.center()
        }
        // Keep above other apps even when Notch is accessory / not key.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Force study window above normal app windows for the whole Focus session.
    private func applyAlwaysOnTop(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
    }
}
