import Cocoa
import SwiftUI

/// Host window for the notch UI. Named distinctly from `NotchPanel` (the tab enum in `NotchPresentationModel`).
final class NotchFloatingPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

/// `NSHostingView` subclass that accepts first mouse clicks so a single
/// click on any SwiftUI control inside the non-activating notch panel
/// triggers the action immediately (no more "need 2 clicks" symptom).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
