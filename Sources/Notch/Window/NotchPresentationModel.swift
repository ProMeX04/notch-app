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
    case shelfQuickLook
    case talkPopover
}

@MainActor
final class NotchPresentationModel: ObservableObject {
    private static let hoverOpenDelayKey = "dev.notch.hover-open-delay-ms"
    private static let autoCollapseDelayKey = "dev.notch.auto-collapse-delay-ms"
    private static let hideInFullscreenKey = "dev.notch.hide-in-fullscreen"

    @Published private(set) var isExpanded = false
    @Published var isPinnedOpen = false
    @Published var closedNotchSize: CGSize = CGSize(width: 184, height: 32)
    @Published var selectedPanel: NotchPanel = .media
    @Published var isFocusOverlayPresented = false
    @Published private(set) var hoverOpenDelayMilliseconds: Double
    @Published private(set) var autoCollapseDelayMilliseconds: Double
    @Published private(set) var accentColorID: String
    @Published private(set) var hideInFullscreen: Bool

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

        accentColorID = NotchAccentColorOption.resolve(
            rawValue: defaults.string(forKey: NotchAccentColorOption.storageKey) ?? ""
        ).rawValue

        hideInFullscreen = defaults.bool(forKey: Self.hideInFullscreenKey)
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

    func setHovering(_ hovering: Bool) {
        isHovering = hovering

        if hovering {
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(hoverDelayDurationMilliseconds))
                guard !Task.isCancelled else { return }
                self.reveal()
            }
            return
        }

        hoverOpenTask?.cancel()
        scheduleCollapse()
    }

    func setHoverOpenDelay(seconds: Double) {
        let milliseconds = min(max(seconds * 1000, 0), 2000)
        hoverOpenDelayMilliseconds = milliseconds
        UserDefaults.standard.set(milliseconds, forKey: Self.hoverOpenDelayKey)
    }

    func setAutoCollapseDelay(seconds: Double) {
        let milliseconds = min(max(seconds * 1000, 0), 5000)
        autoCollapseDelayMilliseconds = milliseconds
        UserDefaults.standard.set(milliseconds, forKey: Self.autoCollapseDelayKey)
    }

    func setAccentColor(_ option: NotchAccentColorOption) {
        accentColorID = option.rawValue
        UserDefaults.standard.set(option.rawValue, forKey: NotchAccentColorOption.storageKey)
    }

    func setHideInFullscreen(_ hide: Bool) {
        hideInFullscreen = hide
        UserDefaults.standard.set(hide, forKey: Self.hideInFullscreenKey)
    }

    func reveal() {
        hoverOpenTask?.cancel()
        collapseTask?.cancel()
        isExpanded = true
    }

    func selectPanel(_ panel: NotchPanel, reveal: Bool = false) {
        selectedPanel = panel
        if panel != .focus {
            isFocusOverlayPresented = false
        }
        if reveal {
            self.reveal()
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

    func togglePinned() {
        isPinnedOpen.toggle()
        if isPinnedOpen {
            reveal()
        } else {
            scheduleCollapse(after: .milliseconds(100))
        }
    }

    private var hoverDelayDurationMilliseconds: Int {
        Int(hoverOpenDelayMilliseconds.rounded())
    }

    private var canAutoCollapse: Bool {
        !isPinnedOpen && autoCollapseSuppressionReasons.isEmpty
    }
}
