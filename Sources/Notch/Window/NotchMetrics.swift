import AppKit
import Foundation

enum NotchMetrics {
    static let openWidth: CGFloat = 640
    static let defaultOpenHeight: CGFloat = 190
    static let shadowPadding: CGFloat = 20
    static let closedCornerRadius: (top: CGFloat, bottom: CGFloat) = (6, 14)
    static let openCornerRadius: (top: CGFloat, bottom: CGFloat) = (19, 24)

    static func openHeight(for _: NotchPanel) -> CGFloat {
        defaultOpenHeight
    }

    static func openSize(for panel: NotchPanel) -> CGSize {
        CGSize(width: openWidth, height: openHeight(for: panel))
    }

    static func windowSize(for panel: NotchPanel) -> CGSize {
        let openSize = openSize(for: panel)
        return CGSize(width: openSize.width, height: openSize.height + shadowPadding)
    }

    static func baseClosedSize(for screen: NSScreen?) -> CGSize {
        guard let screen else {
            return CGSize(width: 184, height: 32)
        }

        var notchHeight = max(30, screen.safeAreaInsets.top)
        var notchWidth: CGFloat = screen.safeAreaInsets.top > 0 ? 192 : 184

        if let topLeftPadding = screen.auxiliaryTopLeftArea?.width,
           let topRightPadding = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeftPadding - topRightPadding + 4
        }

        if screen.safeAreaInsets.top <= 0 {
            notchHeight = max(30, screen.frame.maxY - screen.visibleFrame.maxY)
        }

        return CGSize(width: notchWidth, height: notchHeight)
    }

    static func closedSize(for screen: NSScreen?, showingLiveActivity: Bool) -> CGSize {
        let base = baseClosedSize(for: screen)
        guard showingLiveActivity else { return base }

        let sideInset = max(0, base.height - 12)
        return CGSize(
            width: base.width + (sideInset * 2) - closedCornerRadius.top,
            height: base.height
        )
    }

    static func frame(on screen: NSScreen?, expanded: Bool, showingLiveActivity: Bool, selectedPanel: NotchPanel) -> CGRect {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let size = expanded ? openSize(for: selectedPanel) : closedSize(for: targetScreen, showingLiveActivity: showingLiveActivity)

        guard let targetScreen else {
            return CGRect(origin: .zero, size: size)
        }

        let origin = CGPoint(
            x: targetScreen.frame.midX - (size.width / 2),
            y: targetScreen.frame.maxY - size.height
        )

        return CGRect(origin: origin, size: size)
    }

    static func windowFrame(on screen: NSScreen?, selectedPanel: NotchPanel) -> CGRect {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let windowSize = windowSize(for: selectedPanel)

        guard let targetScreen else {
            return CGRect(origin: .zero, size: windowSize)
        }

        let origin = CGPoint(
            x: targetScreen.frame.midX - (windowSize.width / 2),
            y: targetScreen.frame.maxY - windowSize.height
        )

        return CGRect(origin: origin, size: windowSize)
    }

    static func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
