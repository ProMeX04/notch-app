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
                    panels: [.media, .focus, .talk]
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

            PanelSwitcher(
                presentationModel: presentationModel,
                panels: [.shelf, .settings]
            )
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
                    CompactTalkLiveDot(connectionState: gemini.connectionState)
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
                    isListening: gemini.connectionState == .connected && gemini.effectiveMicrophoneEnabled,
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
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var talkHeaderAccessoryController: NotchHeaderAccessoryController
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if presentationModel.selectedPanel == .focus {
                PomodoroPanelView(
                    pomodoro: pomodoro,
                    learningStats: learningStats,
                    presentationModel: presentationModel
                )
            } else if presentationModel.selectedPanel == .talk {
                GeminiTalkPanelView(
                    gemini: gemini,
                    headerAccessoryController: talkHeaderAccessoryController,
                    presentationModel: presentationModel
                )
            } else if presentationModel.selectedPanel == .shelf {
                ShelfPanelView(
                    shelf: shelf,
                    presentationModel: presentationModel
                )
            } else if presentationModel.selectedPanel == .settings {
                GlobalSettingsView(presentationModel: presentationModel)
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
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct PanelSwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    let panels: [NotchPanel]

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
        case .settings:
            return "gearshape"
        }
    }

    private func switcherButton(icon: String, panel: NotchPanel) -> some View {
        return Button {
            presentationModel.selectPanel(panel)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                .background(
                    Capsule()
                        .fill(presentationModel.selectedPanel == panel ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(switcherTitle(for: panel))
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
        case .settings:
            return "Settings"
        }
    }
}

// MARK: - Localization Support

struct Localization {
    private static let dict: [String: [String: String]] = [
        "General Settings": ["English": "General Settings", "Tiếng Việt": "Cài đặt chung"],
        "General": ["English": "General", "Tiếng Việt": "Chung"],
        "API Keys": ["English": "API Keys", "Tiếng Việt": "API Key"],
        "Language": ["English": "Language", "Tiếng Việt": "Ngôn ngữ"],
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
        "Round": ["English": "Round", "Tiếng Việt": "Vòng"],
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
        "Allow Once": ["English": "Allow Once", "Tiếng Việt": "Cho phép 1 lần"],
        "Once": ["English": "Once", "Tiếng Việt": "1 lần"],
        "Always Exact": ["English": "Always Exact", "Tiếng Việt": "Luôn lệnh này"],
        "Exact": ["English": "Exact", "Tiếng Việt": "Lệnh này"],
        "Always": ["English": "Always", "Tiếng Việt": "Luôn"],
        "Enable All": ["English": "Enable All", "Tiếng Việt": "Bật tất cả"],
        "Disable All": ["English": "Disable All", "Tiếng Việt": "Tắt tất cả"],
        "Manage skills": ["English": "Manage skills", "Tiếng Việt": "Quản lý Skill"],
        "All skills": ["English": "All skills", "Tiếng Việt": "Tất cả Skill"],
        "All tools": ["English": "All tools", "Tiếng Việt": "Tất cả công cụ"],
        "Core Tools": ["English": "Core Tools", "Tiếng Việt": "Công cụ cốt lõi"],
        "New Skill": ["English": "New Skill", "Tiếng Việt": "Kỹ năng mới"],
        "No skills installed": ["English": "No skills installed", "Tiếng Việt": "Chưa cài kỹ năng nào"],
        "No user skills": ["English": "No user skills", "Tiếng Việt": "Không có kỹ năng người dùng"],
        "Share App Window": ["English": "Share App Window", "Tiếng Việt": "Chia sẻ cửa sổ app"],
        "Share Full Screen": ["English": "Share Full Screen", "Tiếng Việt": "Chia sẻ toàn màn hình"],
        "Share Selected Region": ["English": "Share Selected Region", "Tiếng Việt": "Chia sẻ vùng chọn"],
        "Stop Sharing": ["English": "Stop Sharing", "Tiếng Việt": "Dừng chia sẻ"],
        "Name": ["English": "Name", "Tiếng Việt": "Tên"],
        "Agent name (optional)": ["English": "Agent name (optional)", "Tiếng Việt": "Tên trợ lý (không bắt buộc)"],
        "Edit System Prompt": ["English": "Edit System Prompt", "Tiếng Việt": "Sửa lời nhắc hệ thống"],
        "No skills": ["English": "No skills", "Tiếng Việt": "Không có Skill"],
        "No tools": ["English": "No tools", "Tiếng Việt": "Không có công cụ"],
        "Add Skill": ["English": "Add Skill", "Tiếng Việt": "Thêm Skill"],
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
        "Focusing on": ["English": "Focusing on", "Tiếng Việt": "Mục tiêu"],
        "What are you working on?": ["English": "What are you working on?", "Tiếng Việt": "Bạn đang làm việc gì?"],
        "Tasks": ["English": "Tasks", "Tiếng Việt": "Nhiệm vụ"],
        "Add": ["English": "Add", "Tiếng Việt": "Thêm"],
        "No tasks yet": ["English": "No tasks yet", "Tiếng Việt": "Chưa có nhiệm vụ"],
        "Open tasks": ["English": "Open tasks", "Tiếng Việt": "Chưa xong"],
        "Completed tasks": ["English": "Completed", "Tiếng Việt": "Đã xong"],
        "Subscription": ["English": "Subscription", "Tiếng Việt": "Đăng ký"],
        "Notch Pro": ["English": "Notch Pro", "Tiếng Việt": "Notch Pro"],
        "Subscribed": ["English": "Subscribed", "Tiếng Việt": "Đã đăng ký"],
        "Not subscribed": ["English": "Not subscribed", "Tiếng Việt": "Chưa đăng ký"],
        "Subscribe": ["English": "Subscribe", "Tiếng Việt": "Đăng ký"],
        "Restore Purchases": ["English": "Restore Purchases", "Tiếng Việt": "Khôi phục giao dịch"],
        "Subscriptions are billed by Apple. Manage or cancel in System Settings → Apple Account → Subscriptions.": [
            "English": "Subscriptions are billed by Apple. Manage or cancel in System Settings → Apple Account → Subscriptions.",
            "Tiếng Việt": "Thanh toán qua Apple. Quản lý hoặc hủy tại Cài đặt Hệ thống → Tài khoản Apple → Đăng ký.",
        ],
    ]

    static func get(_ key: String, lang: String) -> String {
        return dict[key]?[lang] ?? key
    }
}

// MARK: - Global Settings View

struct GlobalSettingsView: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject private var subscriptionManager = AppStoreSubscriptionManager.shared
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Localization.get("General Settings", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 2)

                generalSettingsSection

                Text("\(Localization.get("Version", lang: appLanguage)) 1.0.0")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            await subscriptionManager.loadOfferings()
        }
    }

    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Localization.get("Subscription", lang: appLanguage))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 2)

            settingsSectionCard(
                title: Localization.get("Notch Pro", lang: appLanguage),
                subtitle: Localization.get(
                    "Subscriptions are billed by Apple. Manage or cancel in System Settings → Apple Account → Subscriptions.",
                    lang: appLanguage
                )
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(
                            subscriptionManager.isProEntitled
                                ? Localization.get("Subscribed", lang: appLanguage)
                                : Localization.get("Not subscribed", lang: appLanguage)
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        if let price = subscriptionManager.subscriptionProduct?.displayPrice {
                            Text(price)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                        }
                    }

                    if let message = subscriptionManager.lastErrorMessage {
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        StandardActionButton(
                            title: Localization.get("Subscribe", lang: appLanguage),
                            icon: "cart",
                            tint: tint,
                            variant: .primary,
                            isDisabled: subscriptionManager.isLoading || subscriptionManager.isProEntitled,
                            fillsAvailableWidth: true
                        ) {
                            Task { await subscriptionManager.purchaseSubscription() }
                        }

                        StandardActionButton(
                            title: Localization.get("Restore Purchases", lang: appLanguage),
                            icon: "arrow.clockwise",
                            tint: tint,
                            variant: .secondary,
                            isDisabled: subscriptionManager.isLoading,
                            fillsAvailableWidth: true
                        ) {
                            Task { await subscriptionManager.restorePurchases() }
                        }
                    }
                }
            }

            settingsSectionCard {
                HStack(spacing: 8) {
                    languageButton(name: "English")
                    languageButton(name: "Tiếng Việt")
                }
                .frame(maxWidth: .infinity)
            }

            settingsSectionCard {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(NotchAccentColorOption.allCases) { option in
                        accentColorButton(for: option)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }

            settingsSectionCard {
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
            }

            settingsSectionCard {
                Toggle(isOn: Binding(
                    get: { presentationModel.hideInFullscreen },
                    set: { presentationModel.setHideInFullscreen($0) }
                )) {
                    Text(Localization.get("Hide in Fullscreen", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .tint(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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

    private var hoverDelayLabel: String {
        String(format: "%.2fs", presentationModel.hoverOpenDelaySeconds)
    }

    private func settingsSectionCard<Content: View>(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if (title != nil && !title!.isEmpty) || (subtitle != nil && !subtitle!.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
