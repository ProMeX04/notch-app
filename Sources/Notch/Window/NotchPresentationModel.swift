import Foundation
import SwiftUI

enum NotchAccentColorOption: String, CaseIterable, Identifiable {
    static let storageKey = "dev.notch.accent-color"

    case blue
    case mint
    case gold
    case coral
    case rose

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
        }
    }

    static func resolve(rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultOption
    }
}

enum NotchPanel: String {
    case music
    case focus
    case talk
    case shelf
    case settings
}

@MainActor
final class NotchPresentationModel: ObservableObject {
    private static let hoverOpenDelayKey = "dev.notch.hover-open-delay-ms"

    @Published private(set) var isExpanded = false
    @Published var isPinnedOpen = false
    @Published var closedNotchSize: CGSize = CGSize(width: 184, height: 32)
    @Published var selectedPanel: NotchPanel = .music
    @Published private(set) var hoverOpenDelayMilliseconds: Double
    @Published private(set) var accentColorID: String

    private var collapseTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.double(forKey: Self.hoverOpenDelayKey)
        if stored > 0 {
            hoverOpenDelayMilliseconds = stored
        } else {
            hoverOpenDelayMilliseconds = 140
        }

        accentColorID = NotchAccentColorOption.resolve(
            rawValue: defaults.string(forKey: NotchAccentColorOption.storageKey) ?? ""
        ).rawValue
    }

    var hoverOpenDelaySeconds: Double {
        hoverOpenDelayMilliseconds / 1000
    }

    var selectedAccentColorOption: NotchAccentColorOption {
        NotchAccentColorOption.resolve(rawValue: accentColorID)
    }

    var accentColor: Color {
        selectedAccentColorOption.color
    }

    func setHovering(_ hovering: Bool) {
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

    func setAccentColor(_ option: NotchAccentColorOption) {
        accentColorID = option.rawValue
        UserDefaults.standard.set(option.rawValue, forKey: NotchAccentColorOption.storageKey)
    }

    func reveal() {
        hoverOpenTask?.cancel()
        collapseTask?.cancel()
        isExpanded = true
    }

    func selectPanel(_ panel: NotchPanel, reveal: Bool = false) {
        selectedPanel = panel
        if reveal {
            self.reveal()
        }
    }

    func scheduleCollapse(after duration: Duration = .milliseconds(900)) {
        collapseTask?.cancel()

        guard !isPinnedOpen else { return }

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isExpanded = false
        }
    }

    func togglePinned() {
        isPinnedOpen.toggle()
        if isPinnedOpen {
            reveal()
        } else {
            scheduleCollapse(after: .milliseconds(100))
        }
    }

    func toggleExpanded() {
        if isExpanded && !isPinnedOpen {
            scheduleCollapse(after: .zero)
        } else {
            reveal()
        }
    }

    private var hoverDelayDurationMilliseconds: Int {
        Int(hoverOpenDelayMilliseconds.rounded())
    }
}
