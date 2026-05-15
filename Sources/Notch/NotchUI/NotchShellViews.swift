import AppKit
import NotchFocusCore
import NotchShelfCore
import SwiftUI

final class NotchHeaderAccessoryController: ObservableObject {
    @Published var leadingActions: [NotchHeaderAction] = []

    func clear() {
        leadingActions = []
    }
}

struct NotchHeaderAction: Identifiable {
    enum Style {
        case secondary
        case primary
    }

    let id: String
    let title: String
    let icon: String?
    let style: Style
    let isDisabled: Bool
    let action: () -> Void
}

struct CompactSpectrumView: View {
    let accentColor: Color
    let isPlaying: Bool

    var body: some View {
        Rectangle()
            .fill(accentColor.gradient)
            .mask {
                AudioSpectrumView(isPlaying: isPlaying)
                    .frame(width: 16, height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PomodoroPhaseProgressIndicator: View {
    enum Style {
        case compact
        case expanded

        var iconSize: CGFloat {
            switch self {
            case .compact: return 15
            case .expanded: return 11
            }
        }

        var stripWidth: CGFloat {
            switch self {
            case .compact: return 26
            case .expanded: return 58
            }
        }

        var stripHeight: CGFloat {
            switch self {
            case .compact: return 6
            case .expanded: return 8
            }
        }

        var segmentCount: Int {
            switch self {
            case .compact: return 5
            case .expanded: return 7
            }
        }

        var framePadding: EdgeInsets {
            switch self {
            case .compact:
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            case .expanded:
                return EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            }
        }

        var contentSpacing: CGFloat {
            switch self {
            case .compact: return 4
            case .expanded: return 8
            }
        }

        var showsContainer: Bool {
            switch self {
            case .compact: return false
            case .expanded: return true
            }
        }
    }

    let phase: PomodoroPhase
    let accentColor: Color
    let progress: Double
    var style: Style = .expanded

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        let content = Group {
            if style == .compact {
                compactPhaseBadge
            } else {
                HStack(spacing: style.contentSpacing) {
                    Image(systemName: phaseIndicatorSymbol)
                        .font(.system(size: style.iconSize, weight: .black))
                        .foregroundStyle(accentColor.opacity(0.9))

                    phaseStrip(progress: clampedProgress)
                }
            }
        }

        content
            .padding(style.framePadding)
            .background {
                if style.showsContainer {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.35))
                }
            }
            .overlay {
                if style.showsContainer {
                    Capsule(style: .continuous)
                        .stroke(accentColor.opacity(0.14), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(phase.rawValue))
    }

    private var phaseIndicatorSymbol: String {
        phase.symbolName
    }

    private var compactPhaseBadge: some View {
        Image(systemName: phaseIndicatorSymbol)
            .font(.system(size: style.iconSize, weight: .black))
            .foregroundStyle(accentColor.opacity(0.94))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phaseStrip(progress: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))

                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.92))
                    .frame(width: width * progress)

                HStack(spacing: max(2, height * 0.22)) {
                    ForEach(0..<style.segmentCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(segmentOpacity(at: index, progress: progress)))
                    }
                }
                .padding(.horizontal, max(2, height * 0.34))
                .padding(.vertical, max(1, height * 0.18))
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(width: style.stripWidth, height: style.stripHeight)
    }

    private func segmentOpacity(at index: Int, progress: Double) -> Double {
        let threshold = Double(index + 1) / Double(style.segmentCount)
        return progress >= threshold ? 0.22 : 0.08
    }
}

struct NotchHeaderView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var accessoryController: NotchHeaderAccessoryController
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var gemini: GeminiLiveViewModel

    private var displayHeight: CGFloat {
        max(22, closedNotchHeight - 6)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(accessoryController.leadingActions) { action in
                    StandardActionButton(
                        title: action.title,
                        icon: action.icon,
                        tint: action.style == .primary ? Color(nsColor: .systemBlue) : .white,
                        variant: action.style == .primary ? .primary : .secondary,
                        isDisabled: action.isDisabled,
                        action: action.action
                    )
                }

                PanelSwitcher(
                    presentationModel: presentationModel,
                    panels: [.media, .focus, .talk],
                    entitlementStore: entitlementStore,
                    pomodoro: pomodoro,
                    gemini: gemini
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .offset(y: 3)

            Rectangle()
                .fill(.clear)
                .frame(width: closedNotchWidth, height: displayHeight)
                .mask {
                    NotchShape()
                }

            HStack(spacing: 10) {
                HeaderUtilitySwitcher(
                    presentationModel: presentationModel,
                    entitlementStore: entitlementStore,
                    gemini: gemini
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .offset(y: 3)
        }
    }

    private func foregroundStyle(for action: NotchHeaderAction) -> Color {
        switch action.style {
        case .secondary:
            return action.isDisabled ? .white.opacity(0.2) : .white.opacity(0.78)
        case .primary:
            return action.isDisabled
                ? .white.opacity(0.2)
                : Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.72)
        }
    }

    private func backgroundFill(for action: NotchHeaderAction) -> Color {
        switch action.style {
        case .secondary:
            return Color.white.opacity(0.04)
        case .primary:
            return Color.white.opacity(0.04)
        }
    }
}

struct CompactLiveActivityView: View {
    @ObservedObject var playback: MediaProbeViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let albumArtNamespace: Namespace.ID

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let albumArt = playback.albumArt {
                    Image(nsImage: albumArt)
                        .resizable()
                        .clipped()
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            CompactSpectrumView(
                accentColor: playback.hasTrack ? Color(nsColor: playback.accentColor) : .gray,
                isPlaying: playback.isPlaying
            )
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactTalkView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private var accentColor: Color {
        Color(nsColor: gemini.compactAccentColor).ensureMinimumBrightness(factor: 0.74)
    }

    private var leadingToolIcon: String? {
        gemini.lastToolAction?.icon
    }

    private var leadingStatusIcon: String? {
        if let leadingToolIcon {
            return leadingToolIcon
        }

        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let leadingStatusIcon {
                    Image(systemName: leadingStatusIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                } else if gemini.isModelThinking {
                    CompactTalkThinkingSpinner(tint: accentColor)
                } else {
                    CompactTalkLiveDot(connectionState: gemini.effectiveConnectionState)
                }
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            HStack {
                Spacer(minLength: 0)
                CompactTalkPulseView(
                    tint: accentColor,
                    inputLevel: gemini.microphoneInputLevel,
                    isListening: gemini.isActivelyListening,
                    isModelSpeaking: gemini.isModelSpeaking
                )
                Spacer(minLength: 0)
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

/// Small “on air” dot for closed notch (no extra chrome — just the dot).
private struct CompactTalkThinkingSpinner: View {
    let tint: Color

    @State private var rotationDegrees: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear {
                rotationDegrees = 0
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotationDegrees = 360
                }
            }
    }
}

/// Small “on air” dot for closed notch (no extra chrome — just the dot).
private struct CompactTalkLiveDot: View {
    let connectionState: GeminiLiveConnectionState
    @State private var pulse = false

    private var dotColor: Color {
        switch connectionState {
        case .connected, .connecting:
            return Color(nsColor: .systemGreen)
        case .failed, .disconnected:
            return Color.white.opacity(0.45)
        }
    }

    private var shouldPulse: Bool {
        switch connectionState {
        case .connecting, .connected:
            return true
        case .failed, .disconnected:
            return false
        }
    }

    private var pulseDuration: Double {
        connectionState == .connecting ? 0.55 : 1.05
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .scaleEffect(shouldPulse && pulse ? 1.14 : 1.0)
            .onAppear {
                guard shouldPulse else { return }
                withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct CompactTalkPulseView: View {
    let tint: Color
    let inputLevel: Double
    let isListening: Bool
    let isModelSpeaking: Bool

    var body: some View {
        if isListening {
            LiveLevelBars(tint: tint, level: inputLevel)
        } else if isModelSpeaking {
            AnimatedPulseBars(tint: tint)
        } else {
            StaticPulseBars(tint: tint)
        }
    }
}

struct LiveLevelBars: View {
    let tint: Color
    let level: Double

    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }

    private var heights: [CGFloat] {
        let floor: CGFloat = 4
        let dynamic = normalizedLevel * 8
        return [
            floor + dynamic * 0.72,
            floor + dynamic,
            floor + dynamic * 0.82
        ]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.96))
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: normalizedLevel)
    }
}

struct StaticPulseBars: View {
    let tint: Color
    private let heights: [CGFloat] = [5, 9, 6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.35))
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
    }
}

struct AnimatedPulseBars: View {
    let tint: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: 3, height: phase ? [10, 5, 12][index] : [5, 11, 7][index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}

struct IdleClosedNotchView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(width: closedNotchWidth, height: closedNotchHeight)
    }
}

struct ExpandedNotchContent: View {
    @ObservedObject var playback: MediaProbeViewModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var talkHeaderAccessoryController: NotchHeaderAccessoryController
    @ObservedObject var shortcutsViewModel: NotchShortcutViewModel
    let albumArtNamespace: Namespace.ID
    let shelfBrowserHost: ShelfBrowserHost

    var body: some View {
        Group {
            if presentationModel.selectedPanel == .focus {
                PomodoroPanelView(
                    pomodoro: pomodoro
                )
            } else if presentationModel.selectedPanel == .talk {
                GeminiTalkPanelView(
                    gemini: gemini,
                    entitlementStore: entitlementStore,
                    headerAccessoryController: talkHeaderAccessoryController,
                    presentationModel: presentationModel
                )
            } else if presentationModel.selectedPanel == .shelf {
                ShelfPanelView(
                    shelf: shelf,
                    presentationModel: presentationModel,
                    host: shelfBrowserHost
                )
            } else if presentationModel.selectedPanel == .shortcuts {
                ShortcutPanelView(
                    viewModel: shortcutsViewModel,
                    presentationModel: presentationModel
                )
            } else {
                HStack {
                    ExpandedAlbumArtView(
                        playback: playback,
                        albumArtNamespace: albumArtNamespace
                    )
                    .padding(.all, 5)

                    ExpandedMediaControlsView(playback: playback)
                        .drawingGroup()
                        .compositingGroup()
                }
            }
        }
        // The shelf panel hosts a heavy NSCollectionView. Pairing a sliding
        // transition with that view's first-time layout produced visible
        // jitter (collection view content laying itself out while SwiftUI
        // simultaneously moved the whole panel). A simple opacity transition
        // is cheap to render and avoids competing with NSCollectionView
        // initial layout / drop-driven inserts.
        .transition(.opacity)
    }
}

struct PanelSwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    let panels: [NotchPanel]
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(panels, id: \.rawValue) { panel in
                switcherButton(
                    icon: switcherIcon(for: panel),
                    panel: panel
                )
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func switcherIcon(for panel: NotchPanel) -> String {
        switch panel {
        case .media:
            return "playpause"
        case .focus:
            return "timer"
        case .talk:
            return "bubble.left.and.bubble.right"
        case .shelf:
            return "tray.full"
        case .shortcuts:
            return "command"
        }
    }

    private func switcherButton(icon: String, panel: NotchPanel) -> some View {
        return Button {
            guard let cap = capability(for: panel) else {
                presentationModel.selectPanel(panel)
                return
            }

            let decision = entitlementStore.decision(for: cap)
            if decision.isAllowed {
                presentationModel.selectPanel(panel)
            } else {
                NotchProWindowController.shared.show(for: cap, entitlementStore: entitlementStore, gemini: gemini)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                .background(
                    Capsule()
                        .fill(presentationModel.selectedPanel == panel ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
                )
                .contentShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if let badge = badge(for: panel) {
                        PanelActivityBadge(
                            color: badge.color,
                            pulses: badge.pulses
                        )
                        .offset(x: -4, y: 4)
                        .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(switcherTitle(for: panel))
    }

    private func capability(for panel: NotchPanel) -> NotchCapability? {
        switch panel {
        case .media:
            return .mediaControls
        case .focus:
            return .focusPomodoro
        case .talk:
            return .talkConnection
        case .shelf:
            return .shelf
        case .shortcuts:
            return nil
        }
    }

    private func switcherTitle(for panel: NotchPanel) -> String {
        switch panel {
        case .media:
            return "Media"
        case .focus:
            return "Focus"
        case .talk:
            return "Talk"
        case .shelf:
            return ""
        case .shortcuts:
            return "Shortcuts"
        }
    }

    private func badge(for panel: NotchPanel) -> PanelSwitcherBadgeStyle? {
        switch panel {
        case .focus:
            guard pomodoro.isRunning else { return nil }
            return PanelSwitcherBadgeStyle(
                color: pomodoro.phase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.78),
                pulses: true
            )
        case .talk:
            switch gemini.effectiveConnectionState {
            case .connected:
                return PanelSwitcherBadgeStyle(
                    color: Color(nsColor: .systemGreen),
                    pulses: true
                )
            case .connecting:
                return PanelSwitcherBadgeStyle(
                    color: Color(nsColor: .systemOrange),
                    pulses: true
                )
            case .disconnected, .failed:
                return nil
            }
        case .media, .shelf, .shortcuts:
            return nil
        }
    }
}

private struct PanelSwitcherBadgeStyle {
    let color: Color
    let pulses: Bool
}

private struct PanelActivityBadge: View {
    let color: Color
    let pulses: Bool

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.92))
                .frame(width: 10, height: 10)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.5), radius: pulses ? 4 : 0)
                .scaleEffect(pulses && isPulsing ? 1.16 : 1.0)
        }
        .onAppear {
            guard pulses else { return }
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct HeaderUtilitySwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        HStack(spacing: 3) {
            Button {
                let cap = NotchCapability.shelf
                let decision = entitlementStore.decision(for: cap)
                if decision.isAllowed {
                    presentationModel.selectPanel(.shelf)
                } else {
                    NotchProWindowController.shared.show(for: cap, entitlementStore: entitlementStore, gemini: gemini)
                }
            } label: {
                utilityIcon(
                    "tray.full",
                    isSelected: presentationModel.selectedPanel == .shelf
                )
            }
            .buttonStyle(.plain)
            .help("Shelf")

            Button {
                presentationModel.selectPanel(.shortcuts)
            } label: {
                utilityIcon(
                    "command",
                    isSelected: presentationModel.selectedPanel == .shortcuts
                )
            }
            .buttonStyle(.plain)
            .help("Shortcuts")

            Button {
                AppSettingsController.shared.open(tab: .general)
            } label: {
                utilityIcon("gearshape", isSelected: false)
            }
            .buttonStyle(.plain)
            .help(Localization.get("Settings", lang: "English"))
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func utilityIcon(_ systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
            )
            .contentShape(Capsule())
    }
}

// MARK: - Localization Support

struct Localization {
    private static let dict: [String: [String: String]] = [
        "General Settings": ["English": "General Settings", "Tiếng Việt": "Cài đặt chung"],
        "General": ["English": "General", "Tiếng Việt": "Chung"],
        "API Keys": ["English": "API Keys", "Tiếng Việt": "API Key"],
        "Language": ["English": "Language", "Tiếng Việt": "Ngôn ngữ"],
        "Launch at Login": ["English": "Launch at Login", "Tiếng Việt": "Khởi động cùng máy"],
        "Hover to Open": ["English": "Hover to Open", "Tiếng Việt": "Mở khi rê chuột"],
        "Hover Open Delay": ["English": "Hover Open Delay", "Tiếng Việt": "Độ trễ mở khi rê chuột"],
        "Adjust how long the pointer must stay over the notch before it opens.": ["English": "Adjust how long the pointer must stay over the notch before it opens.", "Tiếng Việt": "Chỉnh thời gian con trỏ cần đứng trên notch trước khi nó mở ra."],
        "Accent Color": ["English": "Accent Color", "Tiếng Việt": "Màu nhấn"],
        "Choose the shared accent used for Talk controls and settings buttons.": ["English": "Choose the shared accent used for Talk controls and settings buttons.", "Tiếng Việt": "Chọn màu nhấn chung cho các nút trong Talk và phần cài đặt."],
        "Ocean": ["English": "Ocean", "Tiếng Việt": "Biển xanh"],
        "Mint": ["English": "Mint", "Tiếng Việt": "Bạc hà"],
        "Gold": ["English": "Gold", "Tiếng Việt": "Vàng"],
        "Coral": ["English": "Coral", "Tiếng Việt": "San hô"],
        "Rose": ["English": "Rose", "Tiếng Việt": "Hồng"],
        "Cycle": ["English": "Cycle", "Tiếng Việt": "Chu kỳ"],
        "Version": ["English": "Version", "Tiếng Việt": "Phiên bản"],
        "Focus": ["English": "Focus", "Tiếng Việt": "Tập trung"],
        "Focus Sound": ["English": "Focus Sound", "Tiếng Việt": "Âm đổi focus"],
        "Short": ["English": "Short", "Tiếng Việt": "Nghỉ ngắn"],
        "Long": ["English": "Long", "Tiếng Việt": "Nghỉ dài"],
        "Blocked Websites": ["English": "Blocked Websites", "Tiếng Việt": "Trang web bị chặn"],
        "Enter one domain per line. Example: youtube.com": [
            "English": "Enter one domain per line. Example: youtube.com",
            "Tiếng Việt": "Nhập mỗi domain trên một dòng. Ví dụ: youtube.com",
        ],
        "%d domains synced to Chrome extension": [
            "English": "%d domains synced to Chrome extension",
            "Tiếng Việt": "%d domain đã đồng bộ sang extension Chrome",
        ],
        "Chrome reads this list live while focus is running.": [
            "English": "Chrome reads this list live while focus is running.",
            "Tiếng Việt": "Chrome đọc danh sách này trực tiếp khi focus đang chạy.",
        ],
        "Round": ["English": "Round", "Tiếng Việt": "Vòng"],
        "Time": ["English": "Time", "Tiếng Việt": "Thời gian"],
        "Stats": ["English": "Stats", "Tiếng Việt": "Thống kê"],
        "Settings": ["English": "Settings", "Tiếng Việt": "Cài đặt"],
        "Last 7 Days": ["English": "Last 7 Days", "Tiếng Việt": "7 ngày qua"],
        "Focus on": ["English": "Focus on", "Tiếng Việt": "Tập trung ngày"],
        "Break": ["English": "Break", "Tiếng Việt": "Giải lao"],
        "Pause": ["English": "Pause", "Tiếng Việt": "Tạm dừng"],
        "Resume": ["English": "Resume", "Tiếng Việt": "Tiếp tục"],
        "Start Focus": ["English": "Start Focus", "Tiếng Việt": "Bắt đầu tập trung"],
        "Start": ["English": "Start", "Tiếng Việt": "Bắt đầu"],
        "Reset": ["English": "Reset", "Tiếng Việt": "Đặt lại"],
        "Skip": ["English": "Skip", "Tiếng Việt": "Bỏ qua"],
        "Next": ["English": "Next", "Tiếng Việt": "Tiếp theo"],
        "Auto Start Breaks": ["English": "Auto Start Breaks", "Tiếng Việt": "Tự chạy khi nghỉ"],
        "Auto Start Pomo": ["English": "Auto Start Pomo", "Tiếng Việt": "Tự chạy Pomo"],
        "Auto Breaks": ["English": "Auto Breaks", "Tiếng Việt": "Tự bật nghỉ"],
        "Auto Pomo": ["English": "Auto Pomo", "Tiếng Việt": "Tự bật Pomo"],
        "Focus Session": ["English": "Focus Session", "Tiếng Việt": "Đang tập trung"],
        "Short Break": ["English": "Short Break", "Tiếng Việt": "Giải lao ngắn"],
        "Long Break": ["English": "Long Break", "Tiếng Việt": "Giải lao dài"],
        "Pomodoro": ["English": "Pomodoro", "Tiếng Việt": "Tập trung"],
        "Mon": ["English": "Mon", "Tiếng Việt": "Th 2"],
        "Tue": ["English": "Tue", "Tiếng Việt": "Th 3"],
        "Wed": ["English": "Wed", "Tiếng Việt": "Th 4"],
        "Thu": ["English": "Thu", "Tiếng Việt": "Th 5"],
        "Fri": ["English": "Fri", "Tiếng Việt": "Th 6"],
        "Sat": ["English": "Sat", "Tiếng Việt": "Th 7"],
        "Sun": ["English": "Sun", "Tiếng Việt": "CN"],
        "Back": ["English": "Back", "Tiếng Việt": "Quay lại"],
        "Save": ["English": "Save", "Tiếng Việt": "Lưu"],
        "Profile": ["English": "Profile", "Tiếng Việt": "Hồ sơ"],
        "Tools": ["English": "Tools", "Tiếng Việt": "Công cụ"],
        "Skills": ["English": "Skills", "Tiếng Việt": "Kỹ năng"],
        "Common": ["English": "General", "Tiếng Việt": "Chung"],
        "Push to Talk hint": [
            "English": "Used only in Push to Talk mode while Gemini Live is connected. Shortcuts must include at least one modifier key.",
            "Tiếng Việt": "Chỉ dùng ở chế độ Nhấn để nói khi Gemini Live đang kết nối. Phím tắt cần có ít nhất một phím bổ trợ (⌘, ⌥, ⌃ hoặc ⇧).",
        ],
        "System Prompt": ["English": "System Prompt", "Tiếng Việt": "Lời nhắc hệ thống"],
        "New Agent": ["English": "New Agent", "Tiếng Việt": "Agent mới"],
        "Delete Agent": ["English": "Delete Agent", "Tiếng Việt": "Xóa Agent"],
        "Voice": ["English": "Voice", "Tiếng Việt": "Giọng nói"],
        "Thinking": ["English": "Thinking", "Tiếng Việt": "Suy nghĩ"],
        "Agent": ["English": "Agent", "Tiếng Việt": "Trợ lý"],
        "Manage keys": ["English": "Manage keys", "Tiếng Việt": "Quản lý Key"],
        "Connect": ["English": "Connect", "Tiếng Việt": "Kết nối"],
        "Disconnect": ["English": "Disconnect", "Tiếng Việt": "Ngắt kết nối"],
        "End": ["English": "End", "Tiếng Việt": "Kết thúc"],
        "Open Mic": ["English": "Open Mic", "Tiếng Việt": "Mic"],
        "Push to Talk": ["English": "Push to Talk", "Tiếng Việt": "Nhấn để nói"],
        "Push to Talk key": ["English": "Push to Talk key", "Tiếng Việt": "Phím bấm để nói"],
        "Hold": ["English": "Hold", "Tiếng Việt": "Giữ"],
        "Listening": ["English": "Listening", "Tiếng Việt": "Đang nghe"],
        "Mic": ["English": "Mic", "Tiếng Việt": "Mic"],
        "Muted": ["English": "Muted", "Tiếng Việt": "Tắt tiếng"],
        "Subs": ["English": "Subs", "Tiếng Việt": "Phụ đề"],
        "Subs Off": ["English": "Subs Off", "Tiếng Việt": "Phụ đề Tắt"],
        "Subs Auto": ["English": "Subs Auto", "Tiếng Việt": "Phụ đề Tự ẩn"],
        "Subs Pin": ["English": "Subs Pin", "Tiếng Việt": "Phụ đề Ghim"],
        "Type": ["English": "Type", "Tiếng Việt": "Nhập"],
        "Hide": ["English": "Hide", "Tiếng Việt": "Ẩn"],
        "Pin": ["English": "Pin", "Tiếng Việt": "Ghim"],
        "Context": ["English": "Context", "Tiếng Việt": "Ngữ cảnh"],
        "Gemini is listening...": ["English": "Gemini is listening...", "Tiếng Việt": "Đang nghe..."],
        "Thinking...": ["English": "Thinking...", "Tiếng Việt": "Đang nghĩ..."],
        "Delete Agent?": ["English": "Delete Agent?", "Tiếng Việt": "Xóa trợ lý này?"],
        "Cancel": ["English": "Cancel", "Tiếng Việt": "Hủy"],
        "Delete": ["English": "Delete", "Tiếng Việt": "Xóa"],
        "Back to Home": ["English": "Back to Home", "Tiếng Việt": "Trang chủ"],
        "Nothing Playing": ["English": "Nothing Playing", "Tiếng Việt": "Không có nội dung"],
        "System Media": ["English": "System Media", "Tiếng Việt": "Hệ thống"],
        "Done": ["English": "Done", "Tiếng Việt": "Xong"],
        "Gemini Live needs a Gemini API key.": ["English": "Gemini Live needs a Gemini API key.", "Tiếng Việt": "Gemini Live cần một API Key."],
        "Keys are not entered in the notch. Use the menu bar or Manage keys below.": ["English": "Keys are not entered in the notch. Use the menu bar or Manage keys below.", "Tiếng Việt": "Key không thể nhập tại Notch. Hãy dùng Menu Bar hoặc nút Quản lý Key bên dưới."],
        "Approve Command": ["English": "Approve Command", "Tiếng Việt": "Phê duyệt lệnh"],
        "Deny": ["English": "Deny", "Tiếng Việt": "Từ chối"],
        "Gemini API Key": ["English": "Gemini API Key", "Tiếng Việt": "Gemini API Key"],
        "Saved": ["English": "Saved", "Tiếng Việt": "Đã lưu"],
        "Save API key to local": ["English": "Save API key to local", "Tiếng Việt": "Lưu API Key vào máy"],
        "Allow Once": ["English": "Allow Once", "Tiếng Việt": "Cho phép 1 lần"],
        "Once": ["English": "Once", "Tiếng Việt": "1 lần"],
        "Always Exact": ["English": "Always Exact", "Tiếng Việt": "Luôn lệnh này"],
        "Exact": ["English": "Exact", "Tiếng Việt": "Lệnh này"],
        "Always": ["English": "Always", "Tiếng Việt": "Luôn"],
        "Enable All": ["English": "Enable All", "Tiếng Việt": "Bật tất cả"],
        "Disable All": ["English": "Disable All", "Tiếng Việt": "Tắt tất cả"],
        "All skills": ["English": "All skills", "Tiếng Việt": "Tất cả Skill"],
        "All tools": ["English": "All tools", "Tiếng Việt": "Tất cả công cụ"],
        "Core Tools": ["English": "Core Tools", "Tiếng Việt": "Công cụ cốt lõi"],
        "New Skill": ["English": "New Skill", "Tiếng Việt": "Kỹ năng mới"],
        "No skills installed": ["English": "No skills installed", "Tiếng Việt": "Chưa cài kỹ năng nào"],
        "Share App Window": ["English": "Share App Window", "Tiếng Việt": "Chia sẻ cửa sổ app"],
        "Share Full Screen": ["English": "Share Full Screen", "Tiếng Việt": "Chia sẻ toàn màn hình"],
        "Share Selected Region": ["English": "Share Selected Region", "Tiếng Việt": "Chia sẻ vùng chọn"],
        "Stop Sharing": ["English": "Stop Sharing", "Tiếng Việt": "Dừng chia sẻ"],
        "Name": ["English": "Name", "Tiếng Việt": "Tên"],
        "Agent name (optional)": ["English": "Agent name (optional)", "Tiếng Việt": "Tên trợ lý (không bắt buộc)"],
        "Edit System Prompt": ["English": "Edit System Prompt", "Tiếng Việt": "Sửa lời nhắc hệ thống"],
        "No skills": ["English": "No skills", "Tiếng Việt": "Không có Skill"],
        "No tools": ["English": "No tools", "Tiếng Việt": "Không có công cụ"],
        "Clear": ["English": "Clear", "Tiếng Việt": "Xóa trắng"],
        "Change Photo": ["English": "Change Photo", "Tiếng Việt": "Đổi ảnh"],
        "Default": ["English": "Default", "Tiếng Việt": "Mặc định"],
        "Search": ["English": "Search", "Tiếng Việt": "Tìm kiếm"],
        "Read": ["English": "Read", "Tiếng Việt": "Đọc"],
        "Write": ["English": "Write", "Tiếng Việt": "Ghi"],
        "List": ["English": "List", "Tiếng Việt": "Liệt kê"],
        "Find": ["English": "Find", "Tiếng Việt": "Tìm file"],
        "Grep": ["English": "Grep", "Tiếng Việt": "Tìm nội dung"],
        "Edit": ["English": "Edit", "Tiếng Việt": "Sửa"],
        "Calendar": ["English": "Calendar", "Tiếng Việt": "Lịch"],
        "Clipboard": ["English": "Clipboard", "Tiếng Việt": "Bảng tạm"],
        "App": ["English": "App", "Tiếng Việt": "Ứng dụng"],
        "Media": ["English": "Media", "Tiếng Việt": "Phát lại"],
        "Screenshot": ["English": "Screenshot", "Tiếng Việt": "Chụp màn hình"],
        "Browser": ["English": "Browser", "Tiếng Việt": "Trình duyệt"],
        "Local File Search": ["English": "Local File Search", "Tiếng Việt": "Tìm file cục bộ"],
        "Show Result": ["English": "Show Result", "Tiếng Việt": "Hiển thị kết quả"],
        "Skill Writer": ["English": "Skill Writer", "Tiếng Việt": "Tạo Skill"],
        "Exec": ["English": "Exec", "Tiếng Việt": "Chạy lệnh"],
        "Off": ["English": "Off", "Tiếng Việt": "Tắt"],
        "Low": ["English": "Low", "Tiếng Việt": "Thấp"],
        "Medium": ["English": "Medium", "Tiếng Việt": "Vừa"],
        "High": ["English": "High", "Tiếng Việt": "Cao"],
        "Auto-start Breaks": ["English": "Auto-start Breaks", "Tiếng Việt": "Tự động bắt đầu nghỉ"],
        "Auto-start Pomo": ["English": "Auto-start Pomo", "Tiếng Việt": "Tự động bắt đầu Pomodoro"],
        "tools": ["English": "tools", "Tiếng Việt": "công cụ"],
        "skills": ["English": "skills", "Tiếng Việt": "skill"],
        "Auto Hide": ["English": "Auto Hide", "Tiếng Việt": "Tự ẩn"],
        "Quit Notch": ["English": "Quit Notch", "Tiếng Việt": "Thoát Notch"],
        "Hide in Fullscreen": ["English": "Hide in Fullscreen", "Tiếng Việt": "Ẩn ở chế độ toàn màn hình"],
        "User Profile": ["English": "User Profile", "Tiếng Việt": "Hồ sơ cá nhân"],
        "Memory": ["English": "Memory", "Tiếng Việt": "Bộ nhớ"],
        "User Profile (USER.md)": ["English": "User Profile (USER.md)", "Tiếng Việt": "Hồ sơ cá nhân (USER.md)"],
        "Memory (MEMORY.md)": ["English": "Memory (MEMORY.md)", "Tiếng Việt": "Bộ nhớ (MEMORY.md)"],
        "Save User Profile": ["English": "Save User Profile", "Tiếng Việt": "Lưu hồ sơ"],
        "Save Memory": ["English": "Save Memory", "Tiếng Việt": "Lưu bộ nhớ"],
        "Mode": ["English": "Mode", "Tiếng Việt": "Chế độ"],
        "Zen": ["English": "Zen", "Tiếng Việt": "Chìm đắm"],
        "Strict": ["English": "Strict", "Tiếng Việt": "Kỷ luật nghỉ"],
        "Sound": ["English": "Sound", "Tiếng Việt": "Âm thanh"],
        "Streak": ["English": "Streak", "Tiếng Việt": "Chuỗi"],
        "Today": ["English": "Today", "Tiếng Việt": "Hôm nay"],
        "Sessions": ["English": "Sessions", "Tiếng Việt": "Phiên"],
        "Average": ["English": "Average", "Tiếng Việt": "Trung bình"],
        "What are you working on?": ["English": "What are you working on?", "Tiếng Việt": "Bạn đang làm việc gì?"],
        "Tasks": ["English": "Tasks", "Tiếng Việt": "Nhiệm vụ"],
        "Add": ["English": "Add", "Tiếng Việt": "Thêm"],
        "No tasks yet": ["English": "No tasks yet", "Tiếng Việt": "Chưa có nhiệm vụ"],
        "Open tasks": ["English": "Open tasks", "Tiếng Việt": "Chưa xong"],
        "Completed tasks": ["English": "Completed", "Tiếng Việt": "Đã xong"],
        "Subscription": ["English": "Subscription", "Tiếng Việt": "Đăng ký"],
        "Gemini Live": ["English": "Gemini Live", "Tiếng Việt": "Gemini Live"],
        "Gemini Account": ["English": "Gemini Account", "Tiếng Việt": "Tài khoản Gemini"],
        "Talk": ["English": "Talk", "Tiếng Việt": "Trò chuyện"],
        "Floating orb window": [
            "English": "Floating orb window",
            "Tiếng Việt": "Cửa sổ orb nổi",
        ],
        "Show floating orb window when connected": [
            "English": "Show floating orb when session is connected",
            "Tiếng Việt": "Hiện cửa sổ orb nổi khi phiên đang kết nối",
        ],
        "Orb always on top": [
            "English": "Orb always on top",
            "Tiếng Việt": "Orb luôn nổi trên cửa sổ thường",
        ],
        "Show Notch in Dock when orb visible": [
            "English": "Show Notch in Dock while orb window is visible",
            "Tiếng Việt": "Hiện Notch trong Dock khi đang có cửa sổ orb",
        ],
        "Orb appearance": [
            "English": "Orb appearance",
            "Tiếng Việt": "Kiểu orb",
        ],
        "Orb style Ice": [
            "English": "Ice",
            "Tiếng Việt": "Băng",
        ],
        "Orb style Ember": [
            "English": "Ember",
            "Tiếng Việt": "Than lửa",
        ],
        "Orb style Nebula": [
            "English": "Nebula",
            "Tiếng Việt": "Tinh vân",
        ],
        "Orb style Aurora": [
            "English": "Aurora",
            "Tiếng Việt": "Cực quang",
        ],
        "Orb style Mono": [
            "English": "Mono",
            "Tiếng Việt": "Đơn sắc",
        ],
        "Orb style Particle Wave": [
            "English": "Particle Wave",
            "Tiếng Việt": "Sóng hạt",
        ],
        "Orb menu": ["English": "Orb", "Tiếng Việt": "Orb"],
        "Orb menu Show in Dock": [
            "English": "Show Notch in Dock while orb visible",
            "Tiếng Việt": "Hiện Notch trong Dock khi đang có orb",
        ],
        "Orb menu Open Talk settings": [
            "English": "Open Talk settings…",
            "Tiếng Việt": "Mở cài đặt Talk…",
        ],
        "Appearance": ["English": "Appearance", "Tiếng Việt": "Giao diện"],
        "Notch Pro": ["English": "Notch Pro", "Tiếng Việt": "Notch Pro"],
        "Subscribed": ["English": "Subscribed", "Tiếng Việt": "Đã đăng ký"],
        "Not subscribed": ["English": "Not subscribed", "Tiếng Việt": "Chưa đăng ký"],
        "Subscribe": ["English": "Subscribe", "Tiếng Việt": "Đăng ký"],
        "Restore Purchases": ["English": "Restore Purchases", "Tiếng Việt": "Khôi phục giao dịch"],
        "Connection Method": ["English": "Connection Method", "Tiếng Việt": "Kiểu kết nối"],
        "Account": ["English": "Account", "Tiếng Việt": "Tài khoản"],
        "Notch Account": ["English": "Notch Account", "Tiếng Việt": "Tài khoản Notch"],
        "Not signed in": ["English": "Not signed in", "Tiếng Việt": "Chưa đăng nhập"],
        "Manage your Notch account and Pro subscription.": [
            "English": "Manage your Notch account and Pro subscription.",
            "Tiếng Việt": "Quản lý tài khoản Notch và gói Pro.",
        ],
        "Your account has Notch Pro access.": [
            "English": "Your account has Notch Pro access.",
            "Tiếng Việt": "Tài khoản của bạn có quyền Notch Pro.",
        ],
        "Upgrade to Notch Pro to unlock Talk.": [
            "English": "Upgrade to Notch Pro to unlock Talk.",
            "Tiếng Việt": "Nâng cấp Notch Pro để mở khóa Talk.",
        ],
        "Sign in to verify Pro access and sync your subscription.": [
            "English": "Sign in to verify Pro access and sync your subscription.",
            "Tiếng Việt": "Đăng nhập để xác minh quyền Pro và đồng bộ gói đăng ký.",
        ],
        "Managed server uses your Notch Account.": [
            "English": "Managed server uses your Notch Account.",
            "Tiếng Việt": "Máy chủ được quản lý dùng Tài khoản Notch của bạn.",
        ],
        "Sign in and manage Pro from the Account tab.": [
            "English": "Sign in and manage Pro from the Account tab.",
            "Tiếng Việt": "Đăng nhập và quản lý Pro trong tab Tài khoản.",
        ],
        "Open Account Settings": [
            "English": "Open Account Settings",
            "Tiếng Việt": "Mở cài đặt Tài khoản",
        ],
        "Choose how Notch connects to Gemini Live across the app.": [
            "English": "Choose how Notch connects to Gemini Live across the app.",
            "Tiếng Việt": "Chọn cách Notch kết nối tới Gemini Live cho toàn bộ ứng dụng.",
        ],
        "Most people should use Notch Account. API key mode is best for advanced setups.": [
            "English": "Most people should use Notch Account. API key mode is best for advanced setups.",
            "Tiếng Việt": "Hầu hết mọi người nên dùng Tài khoản Notch. Chế độ API key phù hợp hơn cho thiết lập nâng cao.",
        ],
        "Your Gemini API Key": ["English": "Your Gemini API Key", "Tiếng Việt": "Gemini API Key của bạn"],
        "Save API key": ["English": "Save API key", "Tiếng Việt": "Lưu API key"],
        "This key is stored locally on your Mac and used directly by Notch.": [
            "English": "This key is stored locally on your Mac and used directly by Notch.",
            "Tiếng Việt": "Key này được lưu cục bộ trên máy Mac và được Notch dùng trực tiếp.",
        ],
        "Use secure browser sign-in. Notch will complete OAuth 2.0 + PKCE automatically.": [
            "English": "Use secure browser sign-in. Notch will complete OAuth 2.0 + PKCE automatically.",
            "Tiếng Việt": "Dùng đăng nhập an toàn trên trình duyệt. Notch sẽ tự hoàn tất OAuth 2.0 + PKCE.",
        ],
        "No URL or token setup required.": [
            "English": "No URL or token setup required.",
            "Tiếng Việt": "Không cần nhập URL hay token.",
        ],
        "Sign in here once and Talk will reuse this session everywhere in the app.": [
            "English": "Sign in here once and Talk will reuse this session everywhere in the app.",
            "Tiếng Việt": "Đăng nhập một lần ở đây, Talk sẽ dùng lại phiên này ở mọi nơi trong app.",
        ],
        "Continue in your browser. Notch will finish OAuth sign-in automatically.": [
            "English": "Continue in your browser. Notch will finish OAuth sign-in automatically.",
            "Tiếng Việt": "Tiếp tục trong trình duyệt. Notch sẽ tự hoàn tất đăng nhập OAuth.",
        ],
        "Use your own Gemini key if you prefer to connect directly.": [
            "English": "Use your own Gemini key if you prefer to connect directly.",
            "Tiếng Việt": "Dùng Gemini key riêng nếu bạn muốn kết nối trực tiếp.",
        ],
        "Signed in as": ["English": "Signed in as", "Tiếng Việt": "Đăng nhập với"],
        "Log in": ["English": "Log in", "Tiếng Việt": "Đăng nhập"],
        "Sign up": ["English": "Sign up", "Tiếng Việt": "Tạo tài khoản"],
        "Sign out": ["English": "Sign out", "Tiếng Việt": "Đăng xuất"],
        "Open Settings Tab": ["English": "Open Settings Tab", "Tiếng Việt": "Mở tab Cài đặt"],
        "Notch Pro is required to use Talk.": [
            "English": "Notch Pro is required to use Talk.",
            "Tiếng Việt": "Cần Notch Pro để dùng Talk.",
        ],
        "Notch Pro is required to use the hosted Gemini Live server.": [
            "English": "Notch Pro is required to use the hosted Gemini Live server.",
            "Tiếng Việt": "Cần Notch Pro để dùng máy chủ Gemini Live được Notch cung cấp.",
        ],
        "Create account on the web": [
            "English": "Create account on the web",
            "Tiếng Việt": "Tạo tài khoản trên web",
        ],
        "Sign in on the web": [
            "English": "Sign in on the web",
            "Tiếng Việt": "Đăng nhập trên web",
        ],
        "After you sign in on the web, Notch will return automatically.": [
            "English": "After you sign in on the web, Notch will return automatically.",
            "Tiếng Việt": "Sau khi bạn đăng nhập trên web, Notch sẽ tự quay lại.",
        ],
        "Copy-token flow (recommended): on the web sign-in page, the token is copied after login — open Notch, tap Paste from clipboard, then Sign in with token. Or sign in below with email and password.": [
            "English": "Copy-token flow (recommended): on the web sign-in page, the token is copied after login — open Notch, tap Paste from clipboard, then Sign in with token. Or sign in below with email and password.",
            "Tiếng Việt": "Nên dùng: sau khi đăng nhập trên web, token được copy — mở Notch, bấm Dán từ clipboard, rồi Đăng nhập bằng token. Hoặc đăng nhập bên dưới bằng email và mật khẩu.",
        ],
        "Session token": [
            "English": "Session token",
            "Tiếng Việt": "Token phiên",
        ],
        "Paste from clipboard": [
            "English": "Paste from clipboard",
            "Tiếng Việt": "Dán từ clipboard",
        ],
        "Sign in with token": [
            "English": "Sign in with token",
            "Tiếng Việt": "Đăng nhập bằng token",
        ],
        "Invalid or expired session token.": [
            "English": "Invalid or expired session token.",
            "Tiếng Việt": "Token không hợp lệ hoặc đã hết hạn.",
        ],
        "Buy Notch Pro": ["English": "Buy Notch Pro", "Tiếng Việt": "Mua Notch Pro"],
        "Refresh Pro status": [
            "English": "Refresh Pro status",
            "Tiếng Việt": "Cập nhật trạng thái Pro",
        ],
        "Sign in or refresh your Notch account to verify Pro access for Talk.": [
            "English": "Sign in or refresh your Notch account to verify Pro access for Talk.",
            "Tiếng Việt": "Đăng nhập hoặc cập nhật tài khoản Notch để xác minh quyền Pro cho Talk.",
        ],
        "Notch Pro access could not be verified. Refresh your account to continue using Talk.": [
            "English": "Notch Pro access could not be verified. Refresh your account to continue using Talk.",
            "Tiếng Việt": "Không thể xác minh quyền Notch Pro. Hãy cập nhật tài khoản để tiếp tục dùng Talk.",
        ],
        "Offline Pro grace period is active.": [
            "English": "Offline Pro grace period is active.",
            "Tiếng Việt": "Đang dùng thời gian gia hạn Pro khi offline.",
        ],
        "Pro status is expired. Refresh your account to verify access.": [
            "English": "Pro status is expired. Refresh your account to verify access.",
            "Tiếng Việt": "Trạng thái Pro đã hết hạn. Hãy cập nhật tài khoản để xác minh quyền truy cập.",
        ],
        "Pro status has not been verified yet.": [
            "English": "Pro status has not been verified yet.",
            "Tiếng Việt": "Trạng thái Pro chưa được xác minh.",
        ],
        "Weekly Activity": ["English": "Weekly Activity", "Tiếng Việt": "Hoạt động hàng tuần"],
        "Session Timing": ["English": "Session Timing", "Tiếng Việt": "Thời gian phiên"],
        "Automation": ["English": "Automation", "Tiếng Việt": "Tự động hóa"],
        "Allowed Websites": ["English": "Allowed Websites", "Tiếng Việt": "Trang web được cho phép"],
        "Auto-open on Focus Start": ["English": "Auto-open on Focus Start", "Tiếng Việt": "Tự động mở khi tập trung"],
        "Transition Sound": ["English": "Transition Sound", "Tiếng Việt": "Âm thanh chuyển đổi"],
        "Enable Notifications": ["English": "Enable Notifications", "Tiếng Việt": "Bật thông báo"],
        "No allowed websites yet.": ["English": "No allowed websites yet.", "Tiếng Việt": "Chưa có trang web được cho phép."],
        "No auto-open URLs yet.": ["English": "No auto-open URLs yet.", "Tiếng Việt": "Chưa có URL tự động mở."],
        "e.g. music.youtube.com": ["English": "e.g. music.youtube.com", "Tiếng Việt": "ví dụ: music.youtube.com"],
        "e.g. notion.so or https://docs.google.com": ["English": "e.g. notion.so or https://docs.google.com", "Tiếng Việt": "ví dụ: notion.so hoặc https://docs.google.com"],
        "domains will never be blocked": ["English": "domains will never be blocked", "Tiếng Việt": "domain sẽ không bao giờ bị chặn"],
        "URLs will open on focus start": ["English": "URLs will open on focus start", "Tiếng Việt": "URL sẽ tự động mở khi bắt đầu tập trung"],
        "%d domains will never be blocked": ["English": "%d domains will never be blocked", "Tiếng Việt": "%d domain sẽ không bao giờ bị chặn"],
        "%d URLs will open on focus start": ["English": "%d URLs will open on focus start", "Tiếng Việt": "%d URL sẽ tự động mở khi bắt đầu tập trung"],
        "Accent": ["English": "Accent", "Tiếng Việt": "Màu nhấn"],
        "Display": ["English": "Display", "Tiếng Việt": "Hiển thị"],
        "Interaction": ["English": "Interaction", "Tiếng Việt": "Tương tác"],
        "System": ["English": "System", "Tiếng Việt": "Hệ thống"],
        "Auto-Collapse Delay": ["English": "Auto-Collapse Delay", "Tiếng Việt": "Độ trễ tự đóng"],
        "Connection": ["English": "Connection", "Tiếng Việt": "Kết nối"],
        "Saving...": ["English": "Saving...", "Tiếng Việt": "Đang lưu..."],
        "Model": ["English": "Model", "Tiếng Việt": "Mô hình"],
        "Untitled": ["English": "Untitled", "Tiếng Việt": "Chưa đặt tên"],
    ]

    static func get(_ key: String, lang: String) -> String {
        return dict[key]?[lang] ?? key
    }
}

// MARK: - Global Settings View

struct GlobalSettingsView: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    private let launchAtLoginController = LaunchAtLoginController()

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    private var isShowingInlineAuthError: Bool {
        !gemini.isBackendAuthenticated
            && gemini.selectedConnectionMethod == .managedServer
    }
    
    private var appShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                generalSettingsSection

                Text("\(Localization.get("Version", lang: appLanguage)) \(appShortVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if gemini.isBackendAuthenticated {
                            HStack(spacing: 8) {
                                Text(Localization.get(gemini.backendSignedInSummary ?? "Notch Account", lang: appLanguage))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))

                                Text(entitlementStore.planBadgeTitle)
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(entitlementStore.isProUser ? .black.opacity(0.85) : .white.opacity(0.92))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                entitlementStore.isProUser
                                                    ? Color(nsColor: .systemYellow)
                                                    : Color.white.opacity(0.14)
                                            )
                                    )
                                    .overlay {
                                        if !entitlementStore.isProUser {
                                            Capsule(style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        }
                                    }
                            }

                            Button(Localization.get("Sign out", lang: appLanguage)) {
                                Task { await gemini.logoutBackendAccount() }
                            }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Button(Localization.get("Sign in", lang: appLanguage)) {
                                    gemini.openWebAccountLogin()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint)
                                
                                Text(Localization.get("Continue in your browser. Notch will finish OAuth sign-in automatically.", lang: appLanguage))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }

                    Spacer(minLength: 16)

                    if gemini.isBackendAuthenticated && !entitlementStore.isProUser {
                        HStack(spacing: 8) {
                            StandardActionButton(
                                title: Localization.get("Buy Notch Pro", lang: appLanguage),
                                icon: "sparkles",
                                tint: tint,
                                variant: .primary
                            ) {
                                gemini.openWebProCheckout()
                            }

                            Button {
                                Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(tint)
                                    .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(tint.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(Localization.get("Refresh Pro status", lang: appLanguage))
                        }
                    }
                }


                if !gemini.isBackendAuthenticated {
                    VStack(alignment: .leading, spacing: 10) {
                        if let error = gemini.lastErrorMessage ?? gemini.backendAuthFailureMessage, !error.isEmpty {
                            Text(Localization.get(error, lang: appLanguage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                settingsGroupedDivider()

                Text(Localization.get("Appearance", lang: appLanguage))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Localization.get("Language", lang: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))

                            HStack(spacing: 8) {
                                languageButton(name: "English")
                                languageButton(name: "Tiếng Việt")
                            }
                            .frame(maxWidth: .infinity)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(Localization.get("Accent", lang: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(NotchAccentColorOption.allCases) { option in
                                    accentColorButton(for: option)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(Localization.get("Hover to Open", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Text(hoverDelayLabel)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(tint)
                            }

                            Slider(
                                value: Binding(
                                    get: { presentationModel.hoverOpenDelaySeconds },
                                    set: { presentationModel.setHoverOpenDelay(seconds: $0) }
                                ),
                                in: 0.05...1.0,
                                step: 0.05
                            )
                            .tint(tint)
                        }

                        settingsGroupedDivider()

                        Toggle(isOn: Binding(
                            get: { presentationModel.hideInFullscreen },
                            set: { presentationModel.setHideInFullscreen($0) }
                        )) {
                            Text(Localization.get("Hide in Fullscreen", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(NotchSwitchStyle(tint: tint))
                        .frame(maxWidth: .infinity, alignment: .leading)

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { launchAtLoginEnabled },
                                set: { updateLaunchAtLogin(to: $0) }
                            )) {
                                Text(Localization.get("Launch at Login", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .toggleStyle(NotchSwitchStyle(tint: tint))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let launchAtLoginError, !launchAtLoginError.isEmpty {
                                Text(launchAtLoginError)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
            }
            .padding(.horizontal, 13)

            StandardActionButton(
                title: Localization.get("Quit Notch", lang: appLanguage),
                icon: "power",
                tint: Color(nsColor: .systemRed).opacity(0.85),
                variant: .primary,
                fillsAvailableWidth: true
            ) {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsGroupedDivider() -> some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }

    private var hoverDelayLabel: String {
        String(format: "%.2fs", presentationModel.hoverOpenDelaySeconds)
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginController.refreshStatus()
        launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    private func updateLaunchAtLogin(to enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginError = nil
            refreshLaunchAtLoginState()
        } catch {
            launchAtLoginError = error.localizedDescription
            refreshLaunchAtLoginState()
        }
    }

    private func settingsInputCard<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func settingsInlineInputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
    }

    private func languageButton(name: String) -> some View {
        StandardActionButton(
            title: name,
            tint: tint,
            variant: appLanguage == name ? .primary : .secondary,
            action: { appLanguage = name }
        )
    }

    private func accentColorButton(for option: NotchAccentColorOption) -> some View {
        let isSelected = presentationModel.selectedAccentColorOption == option
        let optionColor = option.color.ensureMinimumBrightness(factor: 0.78)

        return Button {
            presentationModel.setAccentColor(option)
        } label: {
            Circle()
                .fill(optionColor)
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
