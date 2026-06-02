import SwiftUI

struct FocusLeaderboardPanelContentView: View {
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    var onClose: () -> Void

    @State private var selectedWindow: String
    @AppStorage("app_language") private var appLanguage: String = "English"
    @Environment(\.colorScheme) private var colorScheme

    init(focusCloudSync: FocusCloudSyncCoordinator, onClose: @escaping () -> Void) {
        self.focusCloudSync = focusCloudSync
        self.onClose = onClose
        self._selectedWindow = State(initialValue: focusCloudSync.leaderboardWindow)
    }

    private var titleText: String {
        appLanguage == "Tiếng Việt" ? "Bảng xếp hạng" : "Leaderboard"
    }

    private var noDataText: String {
        appLanguage == "Tiếng Việt" ? "Chưa có dữ liệu" : "No ranking data yet."
    }

    private var loadingText: String {
        appLanguage == "Tiếng Việt" ? "Đang tải..." : "Loading rankings..."
    }

    private var sessionsLabel: String {
        appLanguage == "Tiếng Việt" ? "phiên" : "sessions"
    }

    var body: some View {
        ZStack {
            LeaderboardGlassSurface(cornerRadius: 20)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Row
                HStack {
                    // Trophy/Title
                    HStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text(titleText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(colorScheme == .light ? .black.opacity(0.85) : .white.opacity(0.9))
                    }

                    Spacer()

                    // Refresh Button / Loading Indicator
                    if focusCloudSync.isFetchingLeaderboard {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .frame(width: 24, height: 24)
                            .padding(2)
                    } else {
                        Button {
                            Task {
                                await focusCloudSync.fetchLeaderboard(window: selectedWindow)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(colorScheme == .light ? .black.opacity(0.55) : .white.opacity(0.65))
                                .padding(6)
                                .background(Circle().fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .help(appLanguage == "Tiếng Việt" ? "Tải lại" : "Refresh")
                    }

                    // Close Button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colorScheme == .light ? .black.opacity(0.55) : .white.opacity(0.65))
                            .padding(6)
                            .background(Circle().fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Window Segmented Control
                HStack(spacing: 0) {
                    SegmentButton(title: appLanguage == "Tiếng Việt" ? "Tuần này" : "Weekly", isSelected: selectedWindow == "week") {
                        selectedWindow = "week"
                    }
                    SegmentButton(title: appLanguage == "Tiếng Việt" ? "Tất cả" : "All-Time", isSelected: selectedWindow == "all") {
                        selectedWindow = "all"
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 9).fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.08)))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // List content
                ZStack {
                    if focusCloudSync.isFetchingLeaderboard && focusCloudSync.leaderboardEntries.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text(loadingText)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(colorScheme == .light ? .black.opacity(0.45) : .white.opacity(0.55))
                        }
                    } else if focusCloudSync.leaderboardEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "crown.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(colorScheme == .light ? .black.opacity(0.2) : .white.opacity(0.3))
                            Text(noDataText)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(colorScheme == .light ? .black.opacity(0.45) : .white.opacity(0.55))
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(focusCloudSync.leaderboardEntries) { entry in
                                    LeaderboardRow(
                                        entry: entry,
                                        isMe: entry.displayName == focusCloudSync.displayName && entry.displayName != "Ẩn danh",
                                        sessionsLabel: sessionsLabel
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 360, height: 480)
        .onAppear {
            Task {
                await focusCloudSync.fetchLeaderboard(window: selectedWindow)
            }
        }
        .onChange(of: selectedWindow) { oldValue, newValue in
            Task {
                await focusCloudSync.fetchLeaderboard(window: newValue)
            }
        }
    }
}

// MARK: - Components

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? (colorScheme == .light ? .black.opacity(0.85) : .white) : (colorScheme == .light ? .black.opacity(0.45) : .white.opacity(0.55)))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? (colorScheme == .light ? Color.white : Color.white.opacity(0.15)) : Color.clear)
                        .shadow(color: isSelected ? (colorScheme == .light ? Color.black.opacity(0.08) : Color.black.opacity(0.2)) : Color.clear, radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct LeaderboardRow: View {
    let entry: FocusLeaderboardEntry
    let isMe: Bool
    let sessionsLabel: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Rank indicator
            RankMedalView(rank: entry.rank)

            // Avatar
            AvatarView(avatarURLString: entry.avatarURL, displayName: entry.displayName, size: 30)

            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: isMe ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isMe ? Color.orange : (colorScheme == .light ? .black.opacity(0.85) : .white.opacity(0.9)))
                    .lineLimit(1)
                
                Text("\(entry.sessionCount) \(sessionsLabel)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(colorScheme == .light ? .black.opacity(0.45) : .white.opacity(0.55))
            }

            Spacer()

            // Time Spent
            Text(formatDuration(entry.focusSeconds))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(colorScheme == .light ? .black.opacity(0.75) : .white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isMe ? Color.orange.opacity(colorScheme == .light ? 0.08 : 0.15) : (colorScheme == .light ? Color.black.opacity(0.03) : Color.white.opacity(0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMe ? Color.orange.opacity(colorScheme == .light ? 0.3 : 0.5) : (colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.1)), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
}

private struct RankMedalView: View {
    let rank: Int
    @Environment(\.colorScheme) private var colorScheme

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.88, blue: 0.45), Color(red: 1.0, green: 0.72, blue: 0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var silverGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.94, green: 0.94, blue: 0.96), Color(red: 0.65, green: 0.65, blue: 0.70)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bronzeGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.88, green: 0.64, blue: 0.49), Color(red: 0.54, green: 0.31, blue: 0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .foregroundStyle(goldGradient)
                    .font(.system(size: 14))
            } else if rank == 2 {
                Image(systemName: "medal.fill")
                    .foregroundStyle(silverGradient)
                    .font(.system(size: 14))
            } else if rank == 3 {
                Image(systemName: "medal.fill")
                    .foregroundStyle(bronzeGradient)
                    .font(.system(size: 14))
            } else {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(colorScheme == .light ? .black.opacity(0.45) : .white.opacity(0.55))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 20, height: 20)
    }
}

private struct AvatarView: View {
    let avatarURLString: String?
    let displayName: String
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if let urlString = avatarURLString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    defaultAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            defaultAvatar
        }
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.12))
            if displayName == "Ẩn danh" {
                Image(systemName: "person.badge.shield.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(colorScheme == .light ? .black.opacity(0.4) : .white.opacity(0.5))
            } else {
                Text(initials(displayName))
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .light ? .black.opacity(0.6) : .white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
    }
    
    private func initials(_ name: String) -> String {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces)
        let filtered = words.filter { !$0.isEmpty }
        if filtered.isEmpty { return "?" }
        if filtered.count == 1 { return String(filtered[0].prefix(2).uppercased()) }
        let first = filtered[0].prefix(1)
        let last = filtered[filtered.count - 1].prefix(1)
        return String((first + last).uppercased())
    }
}

private struct LeaderboardGlassSurface: View {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(colorScheme == .light ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
            VisualEffectView(
                material: colorScheme == .light ? .windowBackground : .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: cornerRadius
            )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .light 
                            ? [Color.white.opacity(0.3), Color.white.opacity(0.1)]
                            : [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.overlay)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(colorScheme == .light ? Color.white.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(colorScheme == .light ? Color.black.opacity(0.12) : Color.black.opacity(0.3), lineWidth: 0.5)
        }
    }
}
