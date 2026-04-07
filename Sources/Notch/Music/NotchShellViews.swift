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
            HStack {
                ForEach(accessoryController.leadingActions) { action in
                    Button(action: action.action) {
                        HStack(spacing: 5) {
                            if let icon = action.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(action.title)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(foregroundStyle(for: action))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(backgroundFill(for: action))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(action.isDisabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .offset(y: 3)

            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth, height: displayHeight)
                .mask {
                    NotchShape()
                }

            HStack(spacing: 4) {
                PanelSwitcher(presentationModel: presentationModel)
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
    @ObservedObject var playback: MusicProbeViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let albumArtNamespace: Namespace.ID

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: playback.albumArt)
                .resizable()
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
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

struct CompactPomodoroView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private var accentColor: Color {
        Color(nsColor: pomodoro.phase.accentColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor.gradient)

                Image(systemName: pomodoro.phase.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .overlay {
                    HStack {
                        Spacer(minLength: 0)

                        PomodoroTimeText(
                            pomodoro: pomodoro,
                            size: 12,
                            weight: .semibold
                        )
                        .foregroundStyle(.white)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            ZStack {
                Circle()
                    .fill(accentColor.opacity(pomodoro.isRunning ? 0.18 : 0.1))

                Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
            }
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

    var body: some View {
        HStack(spacing: 0) {
            CompactTalkLiveDot(connectionState: gemini.connectionState)
                .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            HStack {
                Spacer(minLength: 0)
                CompactTalkPulseView(
                    tint: accentColor,
                    isAnimated: gemini.isModelSpeaking
                )
                Spacer(minLength: 0)
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
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
    let isAnimated: Bool

    var body: some View {
        if isAnimated {
            AnimatedPulseBars(tint: tint)
        } else {
            StaticPulseBars(tint: tint)
        }
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
    @ObservedObject var playback: MusicProbeViewModel
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
                    learningStats: learningStats
                )
            } else if presentationModel.selectedPanel == .talk {
                GeminiTalkPanelView(
                    gemini: gemini,
                    headerAccessoryController: talkHeaderAccessoryController
                )
            } else if presentationModel.selectedPanel == .shelf {
                ShelfPanelView(shelf: shelf)
            } else if presentationModel.selectedPanel == .settings {
                GlobalSettingsView(gemini: gemini)
            } else {
                HStack {
                    ExpandedAlbumArtView(
                        playback: playback,
                        albumArtNamespace: albumArtNamespace
                    )
                    .padding(.all, 5)

                    ExpandedMusicControlsView(playback: playback)
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

    var body: some View {
        HStack(spacing: 3) {
            switcherButton(
                icon: "playpause",
                panel: .music
            )
            switcherButton(
                icon: "timer",
                panel: .focus
            )
            switcherButton(
                icon: "waveform.and.mic",
                panel: .talk
            )
            switcherButton(
                icon: "tray.full",
                panel: .shelf
            )
            switcherButton(
                icon: "gearshape",
                panel: .settings
            )
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

    private func switcherButton(icon: String, panel: NotchPanel) -> some View {
        return Button {
            presentationModel.selectPanel(panel)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
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
        case .music:
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
        "Language": ["English": "Language", "Tiếng Việt": "Ngôn ngữ"],
        "Version": ["English": "Version", "Tiếng Việt": "Phiên bản"],
        "Focus": ["English": "Focus", "Tiếng Việt": "Tập trung"],
        "Short": ["English": "Short", "Tiếng Việt": "Nghỉ ngắn"],
        "Long": ["English": "Long", "Tiếng Việt": "Nghỉ dài"],
        "Stats": ["English": "Stats", "Tiếng Việt": "Thống kê"],
        "Settings": ["English": "Settings", "Tiếng Việt": "Cài đặt"],
        "Last 7 Days": ["English": "Last 7 Days", "Tiếng Việt": "7 ngày qua"],
        "Focus on": ["English": "Focus on", "Tiếng Việt": "Tập trung ngày"],
        "Break": ["English": "Break", "Tiếng Việt": "Giải lao"],
        "Pause": ["English": "Pause", "Tiếng Việt": "Tạm dừng"],
        "Start": ["English": "Start", "Tiếng Việt": "Bắt đầu"],
        "Skip": ["English": "Skip", "Tiếng Việt": "Bỏ qua"],
        "Next": ["English": "Next", "Tiếng Việt": "Tiếp theo"],
        "Auto-start Breaks": ["English": "Auto-start Breaks", "Tiếng Việt": "Tự chạy khi nghỉ"],
        "Auto-start Pomo": ["English": "Auto-start Pomo", "Tiếng Việt": "Tự chạy Pomo"],
        "Focus Session": ["English": "Focus Session", "Tiếng Việt": "Đang tập trung"],
        "Short Break": ["English": "Short Break", "Tiếng Việt": "Giải lao ngắn"],
        "Long Break": ["English": "Long Break", "Tiếng Việt": "Giải lao dài"],
        "Mon": ["English": "Mon", "Tiếng Việt": "Th 2"],
        "Tue": ["English": "Tue", "Tiếng Việt": "Th 3"],
        "Wed": ["English": "Wed", "Tiếng Việt": "Th 4"],
        "Thu": ["English": "Thu", "Tiếng Việt": "Th 5"],
        "Fri": ["English": "Fri", "Tiếng Việt": "Th 6"],
        "Sat": ["English": "Sat", "Tiếng Việt": "Th 7"],
        "Sun": ["English": "Sun", "Tiếng Việt": "CN"],
        "Back": ["English": "Back", "Tiếng Việt": "Quay lại"],
        "Save": ["English": "Save", "Tiếng Việt": "Lưu"],
        "Add": ["English": "Add", "Tiếng Việt": "Thêm"],
        "New Agent": ["English": "New Agent", "Tiếng Việt": "Agent mới"],
        "Delete Agent": ["English": "Delete Agent", "Tiếng Việt": "Xóa Agent"],
        "Voice": ["English": "Voice", "Tiếng Việt": "Giọng nói"],
        "Thinking": ["English": "Thinking", "Tiếng Việt": "Suy nghĩ"],
        "Agent": ["English": "Agent", "Tiếng Việt": "Robot"],
        "Manage keys": ["English": "Manage keys", "Tiếng Việt": "Quản lý Key"],
        "Connect": ["English": "Connect", "Tiếng Việt": "Kết nối"],
        "Disconnect": ["English": "Disconnect", "Tiếng Việt": "Ngắt kết nối"],
        "End": ["English": "End", "Tiếng Việt": "Kết thúc"],
        "Mic": ["English": "Mic", "Tiếng Việt": "Mic"],
        "Muted": ["English": "Muted", "Tiếng Việt": "Tắt tiếng"],
        "Subs": ["English": "Subs", "Tiếng Việt": "Phụ đề"],
        "Type": ["English": "Type", "Tiếng Việt": "Nhập"],
        "Hide": ["English": "Hide", "Tiếng Việt": "Ẩn"],
        "Pin": ["English": "Pin", "Tiếng Việt": "Ghim"],
        "Gemini is listening...": ["English": "Gemini is listening...", "Tiếng Việt": "Đang nghe..."],
        "Thinking...": ["English": "Thinking...", "Tiếng Việt": "Đang nghĩ..."],
        "Delete Agent?": ["English": "Delete Agent?", "Tiếng Việt": "Xóa Robot này?"],
        "Cancel": ["English": "Cancel", "Tiếng Việt": "Hủy"],
        "Delete": ["English": "Delete", "Tiếng Việt": "Xóa"],
        "Back to Home": ["English": "Back to Home", "Tiếng Việt": "Trang chủ"],
        "Nothing Playing": ["English": "Nothing Playing", "Tiếng Việt": "Không có nội dung"],
        "System Media": ["English": "System Media", "Tiếng Việt": "Hệ thống"],
        "Done": ["English": "Done", "Tiếng Việt": "Xong"],
        "Gemini Live needs a Gemini API key.": ["English": "Gemini Live needs a Gemini API key.", "Tiếng Việt": "Gemini Live cần một API Key."],
        "Keys are not entered in the notch. Use the menu bar or Manage keys below.": ["English": "Keys are not entered in the notch. Use the menu bar or Manage keys below.", "Tiếng Việt": "Key không thể nhập tại Notch. Hãy dùng Menu Bar hoặc nút Quản lý Key bên dưới."],
        "Deny": ["English": "Deny", "Tiếng Việt": "Từ chối"],
        "Gemini API Key": ["English": "Gemini API Key", "Tiếng Việt": "Gemini API Key"],
        "Pexels API Key": ["English": "Pexels API Key", "Tiếng Việt": "Pexels API Key"],
        "Saved": ["English": "Saved", "Tiếng Việt": "Đã lưu"],
        "Allow Once": ["English": "Allow Once", "Tiếng Việt": "Cho phép 1 lần"],
        "Always Exact": ["English": "Always Exact", "Tiếng Việt": "Duy trì lệnh đúng"],
        "Manage skills": ["English": "Manage skills", "Tiếng Việt": "Quản lý Skill"],
        "All skills": ["English": "All skills", "Tiếng Việt": "Tất cả Skill"],
        "All tools": ["English": "All tools", "Tiếng Việt": "Tất cả công cụ"],
        "Share App Window": ["English": "Share App Window", "Tiếng Việt": "Chia sẻ cửa sổ app"],
        "Share Full Screen": ["English": "Share Full Screen", "Tiếng Việt": "Chia sẻ toàn màn hình"],
        "Share Selected Region": ["English": "Share Selected Region", "Tiếng Việt": "Chia sẻ vùng chọn"],
        "Stop Sharing": ["English": "Stop Sharing", "Tiếng Việt": "Dừng chia sẻ"],
        "Name": ["English": "Name", "Tiếng Việt": "Tên"],
        "Agent name (optional)": ["English": "Agent name (optional)", "Tiếng Việt": "Tên Robot (không bắt buộc)"],
        "Edit System Prompt": ["English": "Edit System Prompt", "Tiếng Việt": "Sửa thiết lập Robot"],
        "No skills": ["English": "No skills", "Tiếng Việt": "Không có Skill"],
        "No tools": ["English": "No tools", "Tiếng Việt": "Không có công cụ"],
        "Add Skill": ["English": "Add Skill", "Tiếng Việt": "Thêm Skill"],
        "Clear": ["English": "Clear", "Tiếng Việt": "Xóa trắng"],
        "Change Photo": ["English": "Change Photo", "Tiếng Việt": "Đổi ảnh"],
        "Default": ["English": "Default", "Tiếng Việt": "Mặc định"],
        "Search": ["English": "Search", "Tiếng Việt": "Tìm kiếm"],
        "Read": ["English": "Read", "Tiếng Việt": "Đọc"],
        "Write": ["English": "Write", "Tiếng Việt": "Ghi"],
        "Find": ["English": "Find", "Tiếng Việt": "Tìm file"],
        "Grep": ["English": "Grep", "Tiếng Việt": "Tìm nội dung"],
        "Edit": ["English": "Edit", "Tiếng Việt": "Sửa"],
        "Exec": ["English": "Exec", "Tiếng Việt": "Chạy lệnh"],
        "Off": ["English": "Off", "Tiếng Việt": "Tắt"],
        "Low": ["English": "Low", "Tiếng Việt": "Thấp"],
        "Medium": ["English": "Medium", "Tiếng Việt": "Vừa"],
        "High": ["English": "High", "Tiếng Việt": "Cao"],
        "tools": ["English": "tools", "Tiếng Việt": "công cụ"],
        "skills": ["English": "skills", "Tiếng Việt": "skill"],
    ]

    static func get(_ key: String, lang: String) -> String {
        return dict[key]?[lang] ?? key
    }
}

// MARK: - Global Settings View

struct GlobalSettingsView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @AppStorage("app_language") private var appLanguage: String = "English"
    let tint: Color = .blue
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    languageButton(name: "English")
                    languageButton(name: "Tiếng Việt")
                }

                VStack(alignment: .leading, spacing: 12) {
                    settingsTextField(
                        title: "Gemini",
                        placeholder: Localization.get("Gemini API Key", lang: appLanguage),
                        text: $gemini.apiKeyText
                    ) {
                        Task { await gemini.saveAPIKey() }
                    }

                    settingsTextField(
                        title: "Pexels",
                        placeholder: Localization.get("Pexels API Key", lang: appLanguage),
                        text: $gemini.pexelsAPIKeyText
                    ) {
                        Task { await gemini.saveServiceKeys() }
                    }
                }
                
                Spacer()
                
                Text("\(Localization.get("Version", lang: appLanguage)) 1.0.0")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private func settingsTextField(title: String, placeholder: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.32))
                .frame(width: 55, alignment: .leading)

            SecureField(placeholder, text: text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            
            if !text.wrappedValue.isEmpty {
                Button {
                    onCommit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
    
    private func languageButton(name: String) -> some View {
        Button {
            appLanguage = name
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(appLanguage == name ? tint.opacity(0.15) : Color.white.opacity(0.06))
                )
                .overlay {
                    if appLanguage == name {
                        Capsule().stroke(tint.opacity(0.4), lineWidth: 1)
                    }
                }
                .foregroundStyle(appLanguage == name ? tint : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}
