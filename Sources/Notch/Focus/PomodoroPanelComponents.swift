import SwiftUI
import NotchFocusFeature

enum PomodoroPanelMetrics {
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 10
    static let timerFontSize: CGFloat = 88
}

struct PomodoroSimpleFocusPanel: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    let tint: Color
    let namespace: Namespace.ID

    @AppStorage("app_language") private var appLanguage: String = "English"

    private var primaryTitle: String {
        pomodoro.hasActiveSession ? "Resume" : "Start"
    }

    private var streakText: String {
        let days = max(learningStats.streakDays, focusCloudSync.streakDays)
        if appLanguage == "Tiếng Việt" {
            return "\(days) ngày"
        } else {
            return "\(days)d"
        }
    }

    private var rankText: String {
        if focusCloudSync.weeklyRank > 0 {
            return appLanguage == "Tiếng Việt"
                ? "#\(focusCloudSync.weeklyRank) Tuần"
                : "#\(focusCloudSync.weeklyRank) Weekly"
        } else {
            return appLanguage == "Tiếng Việt" ? "Chưa xếp hạng" : "Unranked"
        }
    }

    @State private var isHoveringTrophy = false

    var body: some View {
        HStack(alignment: .center) {
            // LEFT SIDE: Clock / Timer
            PomodoroTimerCluster(pomodoro: pomodoro, tint: tint)
                .matchedGeometryEffect(id: "focus-timer", in: namespace)

            Spacer()

            // RIGHT SIDE: Stats, Phase, and Action Buttons
            VStack(alignment: .leading, spacing: 6) {
                // Phase Name (e.g. "Focus" or "Short Break")
                HStack(spacing: 6) {
                    Image(systemName: pomodoro.phase.symbolName)
                        .foregroundStyle(tint)
                        .font(.system(size: 13, weight: .bold))
                    Text(Localization.get(pomodoro.phase.rawValue, lang: appLanguage))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Stats (Streak and Rank)
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text(streakText)
                    }

                    Text("•")
                        .foregroundStyle(.white.opacity(0.18))

                    Button {
                        NotchWebPortal.openInBrowser(NotchWebPortal.leaderboardURL())
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text(rankText)
                        }
                        .contentShape(Rectangle())
                        .opacity(isHoveringTrophy ? 1.0 : 0.8)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringTrophy = hovering
                        if hovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

                Spacer().frame(height: 4)

                // Buttons
                HStack(spacing: 8) {
                    StandardActionButton(
                        title: Localization.get(primaryTitle, lang: appLanguage),
                        icon: "play.fill",
                        tint: tint,
                        variant: .primary
                    ) {
                        pomodoro.toggleRunning()
                    }

                    if pomodoro.hasActiveSession {
                        StandardActionButton(
                            title: Localization.get("Reset", lang: appLanguage),
                            icon: "arrow.counterclockwise",
                            tint: tint,
                            variant: .secondary
                        ) {
                            pomodoro.reset()
                        }
                    }
                }
            }
        }
        .frame(width: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            Task {
                await focusCloudSync.refreshProfile()
            }
        }
    }
}

struct PomodoroActiveFocusPanel: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    let namespace: Namespace.ID

    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                PomodoroActiveTimerDisplay(
                    pomodoro: pomodoro,
                    tint: tint,
                    date: context.date
                )
                .matchedGeometryEffect(id: "focus-timer", in: namespace)
                .frame(width: 460, height: 96)
            }

            HStack(spacing: 8) {
                // Study is open automatically during Focus — icon is status, not a launch button.
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint.opacity(0.9))
                    .help(Localization.get("Study during Focus", lang: appLanguage))

                StandardActionButton(
                    title: Localization.get("Pause", lang: appLanguage),
                    icon: "pause.fill",
                    tint: tint,
                    variant: .primary
                ) {
                    pomodoro.toggleRunning()
                }

                StandardActionButton(
                    title: Localization.get("Skip", lang: appLanguage),
                    icon: "forward.end.fill",
                    tint: tint,
                    variant: .secondary
                ) {
                    pomodoro.skipPhase()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct PomodoroActiveTimerDisplay: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            PomodoroTimerCluster(pomodoro: pomodoro, tint: tint, date: date)
                .frame(width: 440)
        }
        .frame(width: 480, height: 96)
    }
}

private struct PomodoroTimerCluster: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    var date: Date = .now

    var body: some View {
        VStack(spacing: 5) {
            PomodoroSessionDotsView(
                current: pomodoro.completedSessionsInCycle,
                total: pomodoro.sessionsBeforeLongBreak,
                isFocus: pomodoro.phase == .focus,
                tint: tint,
                dotSize: 3,
                spacing: 4,
                indicatorSize: 16
            )
            PomodoroTimerText(pomodoro: pomodoro, tint: tint, date: date)
        }
    }
}

private struct PomodoroTimerText: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    var date: Date = .now

    var body: some View {
        Text(pomodoro.remainingText(at: date))
            .font(.system(size: PomodoroPanelMetrics.timerFontSize, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .shadow(color: tint.opacity(0.32), radius: 16, x: 0, y: 0) // Increased glow
            .shadow(color: tint.opacity(0.12), radius: 32, x: 0, y: 0)
    }
}
