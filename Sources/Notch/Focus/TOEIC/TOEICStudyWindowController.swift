import AppKit
import SwiftUI

// Uses SwiftUI `Color` for accent wiring into the study root view.

@MainActor
final class TOEICStudyWindowController {
    static let shared = TOEICStudyWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    private init() {}

    func show(tint: Color? = nil) {
        let resolvedTint = tint ?? NotchAccentColorOption.resolve(
            rawValue: UserDefaults.standard.string(forKey: NotchAccentColorOption.storageKey)
                ?? NotchAccentColorOption.defaultOption.rawValue
        ).brightColor

        let root = AnyView(
            TOEICStudyRootView(tint: resolvedTint)
                .frame(minWidth: 440, minHeight: 520)
        )

        if let hosting {
            hosting.rootView = root
        } else {
            let hostingController = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hostingController)
            win.title = ""
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.setContentSize(NSSize(width: 480, height: 580))
            win.isReleasedWhenClosed = false
            win.backgroundColor = NSColor.black
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.titlebarSeparatorStyle = .none
            // Content draws its own single chrome row under the traffic lights.
            win.appearance = NSAppearance(named: .darkAqua)
            win.hidesOnDeactivate = false
            applyAlwaysOnTop(win)
            hosting = hostingController
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
