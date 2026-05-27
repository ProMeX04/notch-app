import SwiftUI
import NotchFocusFeature

enum PomodoroPanelMetrics {
    static let horizontalPadding: CGFloat = 32
    static let verticalPadding: CGFloat = 10
    static let timerFontSize: CGFloat = 88
}

struct PomodoroSimpleFocusPanel: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    let namespace: Namespace.ID

    @AppStorage("app_language") private var appLanguage: String = "English"

    private var primaryTitle: String {
        pomodoro.hasActiveSession ? "Resume" : "Start"
    }

    var body: some View {
        VStack(spacing: 8) {
            PomodoroTimerCluster(pomodoro: pomodoro, tint: tint)
                .matchedGeometryEffect(id: "focus-timer", in: namespace)
                .frame(width: 480)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
