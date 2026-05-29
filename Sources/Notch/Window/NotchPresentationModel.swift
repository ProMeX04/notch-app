import AppKit
import Foundation
import SwiftUI

enum NotchAccentColorOption: String, CaseIterable, Identifiable {
    static let storageKey = "dev.notch.accent-color"

    case blue
    case mint
    case gold
    case coral
    case rose
    case purple
    case indigo
    case green
    case teal
    case cyan

    static let defaultOption: Self = .blue

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .blue:
            return "Ocean"
        case .mint:
            return "Mint"
        case .gold:
            return "Gold"
        case .coral:
            return "Coral"
        case .rose:
            return "Rose"
        case .purple:
            return "Purple"
        case .indigo:
            return "Indigo"
        case .green:
            return "Green"
        case .teal:
            return "Teal"
        case .cyan:
            return "Cyan"
        }
    }

    var color: Color {
        switch self {
        case .blue:
            return Color(nsColor: .systemBlue)
        case .mint:
            return Color(nsColor: .systemMint)
        case .gold:
            return Color(nsColor: .systemYellow)
        case .coral:
            return Color(nsColor: .systemOrange)
        case .rose:
            return Color(nsColor: .systemPink)
        case .purple:
            return Color(nsColor: .systemPurple)
        case .indigo:
            return Color(nsColor: .systemIndigo)
        case .green:
            return Color(nsColor: .systemGreen)
        case .teal:
            return Color(nsColor: .systemTeal)
        case .cyan:
            return Color(nsColor: .systemCyan)
        }
    }

    var brightColor: Color {
        color.ensureMinimumBrightness(factor: 0.78)
    }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .mint: return .systemMint
        case .gold: return .systemYellow
        case .coral: return .systemOrange
        case .rose: return .systemPink
        case .purple: return .systemPurple
        case .indigo: return .systemIndigo
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .cyan: return .systemCyan
        }
    }

    static func resolve(rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultOption
    }
}

struct NotchScreenID: Hashable, Equatable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(screen: NSScreen) {
        if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            rawValue = "display-\(displayID.uint32Value)"
        } else {
            let frame = screen.frame
            rawValue = "frame-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))-\(Int(frame.height))"
        }
    }
}

enum NotchScreenDisplayMode: String, CaseIterable, Identifiable {
    static let storageKey = "dev.notch.screen-display-mode"

    case oneScreen
    case allScreens

    static let defaultOption: Self = .oneScreen

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .oneScreen:
            return "One Screen"
        case .allScreens:
            return "All Screens"
        }
    }

    static func resolve(rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultOption
    }
}

enum NotchInvisibilityMode: String, CaseIterable, Identifiable {
    static let storageKey = "dev.notch.invisibility-mode"

    case off
    case fullscreenOnly
    case always

    static let defaultOption: Self = .off

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .off:
            return "Off"
        case .fullscreenOnly:
            return "Fullscreen"
        case .always:
            return "Invisible Always"
        }
    }

    static func resolve(rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultOption
    }
}

enum NotchPanel: String {
    case media
    case focus
    case talk
    case shelf
}

enum NotchAutoCollapseSuppressionReason: Hashable {
    case talkPopover
}

@MainActor
final class NotchPresentationModel: ObservableObject {
    private static let hoverOpenDelayKey = "dev.notch.hover-open-delay-ms"
    private static let autoCollapseDelayKey = "dev.notch.auto-collapse-delay-ms"
    private static let closedNotchHeightKey = "dev.notch.closed-height-pt"
    private static let hideInFullscreenKey = "dev.notch.hide-in-fullscreen"
    private static let invisibleClosedNotchKey = "dev.notch.invisible-closed-notch"

    @Published private(set) var isExpanded = false
    @Published private(set) var activeScreenID: NotchScreenID?
    @Published private var closedNotchSizeByScreenID: [NotchScreenID: CGSize] = [:]
    @Published private var fullscreenScreenIDs = Set<NotchScreenID>()
    @Published var closedNotchSize: CGSize = CGSize(width: 184, height: 32)
    @Published var selectedPanel: NotchPanel = .media
    @Published var isFocusOverlayPresented = false
    @Published private(set) var hoverOpenDelayMilliseconds: Double
    @Published private(set) var autoCollapseDelayMilliseconds: Double
    @Published private(set) var closedNotchHeight: Double
    @Published private(set) var accentColorID: String
    @Published private(set) var screenDisplayModeID: String
    @Published private(set) var invisibilityModeID: String

    private var collapseTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var isHovering = false
    private var autoCollapseSuppressionReasons = Set<NotchAutoCollapseSuppressionReason>()

    init(defaults: UserDefaults = .standard) {
        let hoverStored = defaults.double(forKey: Self.hoverOpenDelayKey)
        if hoverStored > 0 {
            hoverOpenDelayMilliseconds = hoverStored
        } else {
            hoverOpenDelayMilliseconds = 140
        }

        let collapseStored = defaults.double(forKey: Self.autoCollapseDelayKey)
        if collapseStored > 0 {
            autoCollapseDelayMilliseconds = collapseStored
        } else {
            autoCollapseDelayMilliseconds = 900
        }

        let closedHeightStored = defaults.double(forKey: Self.closedNotchHeightKey)
        if closedHeightStored > 0 {
            closedNotchHeight = Self.clampedClosedNotchHeight(closedHeightStored)
        } else {
            closedNotchHeight = 30
        }

        accentColorID = NotchAccentColorOption.resolve(
            rawValue: defaults.string(forKey: NotchAccentColorOption.storageKey) ?? ""
        ).rawValue

        screenDisplayModeID = NotchScreenDisplayMode.resolve(
            rawValue: defaults.string(forKey: NotchScreenDisplayMode.storageKey) ?? ""
        ).rawValue

        if let storedInvisibilityMode = defaults.string(forKey: NotchInvisibilityMode.storageKey) {
            invisibilityModeID = NotchInvisibilityMode.resolve(rawValue: storedInvisibilityMode).rawValue
        } else if defaults.bool(forKey: Self.invisibleClosedNotchKey) {
            invisibilityModeID = NotchInvisibilityMode.always.rawValue
        } else if defaults.bool(forKey: Self.hideInFullscreenKey) {
            invisibilityModeID = NotchInvisibilityMode.fullscreenOnly.rawValue
        } else {
            invisibilityModeID = NotchInvisibilityMode.defaultOption.rawValue
        }
    }

    var hoverOpenDelaySeconds: Double {
        hoverOpenDelayMilliseconds / 1000
    }

    var autoCollapseDelaySeconds: Double {
        autoCollapseDelayMilliseconds / 1000
    }

    var selectedAccentColorOption: NotchAccentColorOption {
        NotchAccentColorOption.resolve(rawValue: accentColorID)
    }

    var accentColor: Color {
        selectedAccentColorOption.color
    }

    var selectedScreenDisplayMode: NotchScreenDisplayMode {
        NotchScreenDisplayMode.resolve(rawValue: screenDisplayModeID)
    }

    var selectedInvisibilityMode: NotchInvisibilityMode {
        NotchInvisibilityMode.resolve(rawValue: invisibilityModeID)
    }

    var hideInFullscreen: Bool {
        selectedInvisibilityMode == .fullscreenOnly
    }

    var invisibleClosedNotch: Bool {
        selectedInvisibilityMode == .always
    }

    func isExpanded(on screenID: NotchScreenID) -> Bool {
        isExpanded && activeScreenID == screenID
    }

    func closedNotchSize(for screenID: NotchScreenID) -> CGSize {
        closedNotchSizeByScreenID[screenID] ?? closedNotchSize
    }

    func isFullscreenActive(on screenID: NotchScreenID) -> Bool {
        fullscreenScreenIDs.contains(screenID)
    }

    func setFullscreenActive(_ active: Bool, for screenID: NotchScreenID) {
        if active {
            fullscreenScreenIDs.insert(screenID)
        } else {
            fullscreenScreenIDs.remove(screenID)
        }
    }

    func setClosedNotchSize(_ size: CGSize, for screenID: NotchScreenID) {
        closedNotchSizeByScreenID[screenID] = size
        if activeScreenID == nil || activeScreenID == screenID {
            closedNotchSize = size
        }
    }

    func removeScreenState(for screenID: NotchScreenID) {
        closedNotchSizeByScreenID.removeValue(forKey: screenID)
        fullscreenScreenIDs.remove(screenID)
        if activeScreenID == screenID {
            activeScreenID = nil
            isExpanded = false
        }
    }

    func setHovering(_ hovering: Bool, on screenID: NotchScreenID? = nil) {
        isHovering = hovering

        if hovering {
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(hoverDelayDurationMilliseconds))
                guard !Task.isCancelled else { return }
                self.reveal(on: screenID)
            }
            return
        }

        hoverOpenTask?.cancel()
        scheduleCollapse()
    }

    func setHoverOpenDelay(seconds: Double) {
        let milliseconds = min(max(seconds * 1000, 0), 5000)
        hoverOpenDelayMilliseconds = milliseconds
        UserDefaults.standard.set(milliseconds, forKey: Self.hoverOpenDelayKey)
    }

    func setAutoCollapseDelay(seconds: Double) {
        let milliseconds = min(max(seconds * 1000, 0), 5000)
        autoCollapseDelayMilliseconds = milliseconds
        UserDefaults.standard.set(milliseconds, forKey: Self.autoCollapseDelayKey)
    }

    func setClosedNotchHeight(_ height: Double) {
        let clampedHeight = Self.clampedClosedNotchHeight(height)
        closedNotchHeight = clampedHeight
        UserDefaults.standard.set(clampedHeight, forKey: Self.closedNotchHeightKey)
    }

    func setAccentColor(_ option: NotchAccentColorOption) {
        accentColorID = option.rawValue
        UserDefaults.standard.set(option.rawValue, forKey: NotchAccentColorOption.storageKey)
    }

    func setScreenDisplayMode(_ option: NotchScreenDisplayMode) {
        screenDisplayModeID = option.rawValue
        UserDefaults.standard.set(option.rawValue, forKey: NotchScreenDisplayMode.storageKey)
    }

    func setInvisibilityMode(_ option: NotchInvisibilityMode) {
        invisibilityModeID = option.rawValue
        UserDefaults.standard.set(option.rawValue, forKey: NotchInvisibilityMode.storageKey)
        UserDefaults.standard.set(option == .fullscreenOnly, forKey: Self.hideInFullscreenKey)
        UserDefaults.standard.set(option == .always, forKey: Self.invisibleClosedNotchKey)
    }

    private static func clampedClosedNotchHeight(_ height: Double) -> Double {
        min(max(height, 1), 32)
    }

    func reveal(on screenID: NotchScreenID? = nil) {
        hoverOpenTask?.cancel()
        collapseTask?.cancel()
        if let screenID {
            activeScreenID = screenID
            closedNotchSize = closedNotchSize(for: screenID)
        }
        isExpanded = true
    }

    func selectPanel(_ panel: NotchPanel, on screenID: NotchScreenID? = nil, reveal: Bool = false) {
        selectedPanel = panel
        if panel != .focus {
            isFocusOverlayPresented = false
        }
        if reveal {
            self.reveal(on: screenID)
        } else if let screenID {
            activeScreenID = screenID
            closedNotchSize = closedNotchSize(for: screenID)
        }
    }

    func scheduleCollapse(after duration: Duration? = nil) {
        collapseTask?.cancel()

        guard canAutoCollapse else { return }

        let finalDuration = duration ?? .milliseconds(Int(autoCollapseDelayMilliseconds.rounded()))

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: finalDuration)
            guard !Task.isCancelled else { return }
            guard self.canAutoCollapse else { return }
            isExpanded = false
        }
    }

    /// Cancel any pending auto-collapse without re-scheduling. Used when
    /// AppKit's `NSCollectionView` consumes a drop directly (bypassing
    /// SwiftUI's `onDrop`) — in that path the drop-target leave event has
    /// already armed a collapse before we know the drop was successful.
    func cancelScheduledCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    func setAutoCollapseSuppressed(_ suppressed: Bool, reason: NotchAutoCollapseSuppressionReason) {
        if suppressed {
            let inserted = autoCollapseSuppressionReasons.insert(reason).inserted
            if inserted {
                collapseTask?.cancel()
            }
            return
        }

        let removed = autoCollapseSuppressionReasons.remove(reason) != nil
        guard removed else { return }
        guard canAutoCollapse, !isHovering else { return }
        scheduleCollapse(after: .milliseconds(120))
    }

    private var hoverDelayDurationMilliseconds: Int {
        Int(hoverOpenDelayMilliseconds.rounded())
    }

    private var canAutoCollapse: Bool {
        autoCollapseSuppressionReasons.isEmpty
    }
}
