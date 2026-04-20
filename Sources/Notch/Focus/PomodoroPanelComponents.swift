import SwiftUI
import NotchFocusCore

enum PomodoroPanelMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 8
    static let contentSpacing: CGFloat = 8
    static let timerFontSize: CGFloat = 58
    static let taskFontSize: CGFloat = 16
}

struct PomodoroPanelHeader: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color

    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(spacing: 4) {
            Text(Localization.get(pomodoro.phase.rawValue, lang: appLanguage))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .tracking(1.0)

            if pomodoro.hasActiveSession {
                HStack(spacing: 8) {
                    PomodoroSessionDotsView(
                        current: pomodoro.completedSessionsInCycle,
                        total: pomodoro.sessionsBeforeLongBreak,
                        isFocus: pomodoro.phase == .focus,
                        tint: tint
                    )

                    Text("\(Localization.get("Round", lang: appLanguage)) \(pomodoro.currentFocusSessionIndex)/\(pomodoro.sessionsBeforeLongBreak)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.82))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PomodoroPanelTimer: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(pomodoro.remainingText(at: context.date))
                .font(.system(size: PomodoroPanelMetrics.timerFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4), value: pomodoro.remainingSeconds)
                .shadow(color: tint.opacity(0.26), radius: 24, x: 0, y: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PomodoroPanelTaskChip: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color

    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        if !pomodoro.currentTask.isEmpty {
            VStack(spacing: 6) {
                Text(Localization.get("Focusing on", lang: appLanguage).uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(tint.opacity(0.7))
                    .tracking(2.5)

                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)

                Text(pomodoro.currentTask)
                    .font(.system(size: PomodoroPanelMetrics.taskFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct PomodoroPanelDock: View {
    enum State {
        case idle
        case paused
        case running
    }

    let state: State
    let phaseTint: Color
    let interfaceTint: Color
    let onPrimaryAction: () -> Void
    let onReset: () -> Void
    let onStats: () -> Void
    let onSettings: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .running:
                StandardActionButton(
                    title: Localization.get("Pause", lang: appLanguage),
                    icon: "pause.fill",
                    tint: interfaceTint,
                    variant: .primary,
                    fillsAvailableWidth: true,
                    action: onPrimaryAction
                )

                StandardActionButton(
                    title: Localization.get("Skip", lang: appLanguage),
                    icon: "forward.end.fill",
                    tint: phaseTint,
                    variant: .secondary,
                    fillsAvailableWidth: true,
                    action: onSkip
                )

            case .paused:
                StandardActionButton(
                    title: Localization.get("Resume", lang: appLanguage),
                    icon: "play.fill",
                    tint: interfaceTint,
                    variant: .primary,
                    fillsAvailableWidth: true,
                    action: onPrimaryAction
                )

                standardSecondaryButtons

            case .idle:
                StandardActionButton(
                    title: Localization.get("Start", lang: appLanguage),
                    icon: "play.fill",
                    tint: interfaceTint,
                    variant: .primary,
                    fillsAvailableWidth: true,
                    action: onPrimaryAction
                )

                standardSecondaryButtons
            }
        }
        .frame(maxWidth: .infinity)
    }

    @AppStorage("app_language") private var appLanguage: String = "English"

    @ViewBuilder
    private var standardSecondaryButtons: some View {
        StandardActionButton(
            title: Localization.get("Reset", lang: appLanguage),
            icon: "arrow.counterclockwise",
            tint: interfaceTint,
            variant: .secondary,
            fillsAvailableWidth: true,
            action: onReset
        )

        StandardActionButton(
            title: Localization.get("Stats", lang: appLanguage),
            icon: "chart.bar.xaxis",
            tint: interfaceTint,
            variant: .secondary,
            fillsAvailableWidth: true,
            action: onStats
        )

        StandardActionButton(
            title: Localization.get("Settings", lang: appLanguage),
            icon: "slider.horizontal.3",
            tint: interfaceTint,
            variant: .secondary,
            fillsAvailableWidth: true,
            action: onSettings
        )
    }
}
