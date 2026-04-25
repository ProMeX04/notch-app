import SwiftUI
import NotchFocusCore

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
        HStack(spacing: 32) {
            Spacer(minLength: 0)

            PomodoroTimerCluster(pomodoro: pomodoro, tint: tint)
                .matchedGeometryEffect(id: "focus-timer", in: namespace)
                .frame(width: 480)

            VStack(spacing: 8) {
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
            .frame(width: 140, alignment: .leading)

            Spacer(minLength: 0)
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
        HStack(spacing: 32) {
            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                PomodoroProgressClock(
                    pomodoro: pomodoro,
                    tint: tint,
                    date: context.date
                )
                .matchedGeometryEffect(id: "focus-timer", in: namespace)
                .frame(width: 460, height: 168)
            }

            VStack(spacing: 8) {
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
            .frame(width: 140, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct PomodoroProgressClock: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    let date: Date

    private var totalSeconds: Int {
        switch pomodoro.phase {
        case .focus:
            return pomodoro.focusDurationSeconds
        case .shortBreak:
            return pomodoro.breakDurationSeconds
        case .longBreak:
            return pomodoro.longBreakDurationSeconds
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PomodoroTimerCluster(pomodoro: pomodoro, tint: tint, date: date)
                .frame(width: 440)
        }
        .frame(width: 480, height: 160)
    }
}

private struct PomodoroTimerCluster: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    var date: Date = .now

    var body: some View {
        HStack(spacing: 32) {
            PomodoroClockGlyph(
                tint: tint,
                totalAngle: clockProgressAngle,
                minuteAngle: minuteProgressAngle,
                isRunning: pomodoro.isRunning
            )

            PomodoroTimerText(pomodoro: pomodoro, tint: tint, date: date)
        }
    }

    private var clockProgressAngle: Double {
        let total: Int
        switch pomodoro.phase {
        case .focus:
            total = pomodoro.focusDurationSeconds
        case .shortBreak:
            total = pomodoro.breakDurationSeconds
        case .longBreak:
            total = pomodoro.longBreakDurationSeconds
        }
        
        let remaining = Double(pomodoro.remainingSeconds(at: date))
        let totalDuration = Double(max(total, 1))
        // Positive angle for counter-clockwise rotation as time counts down
        return (remaining / totalDuration) * 360.0
    }

    private var minuteProgressAngle: Double {
        let remaining = Double(pomodoro.remainingSeconds(at: date))
        // 6 degrees per second for counter-clockwise movement
        return remaining * 6.0
    }
}

private struct PomodoroClockGlyph: View {
    let tint: Color
    let totalAngle: Double
    let minuteAngle: Double
    let isRunning: Bool

    var body: some View {
        ZStack {
            // Background ambient glow from the tinted ring
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 140, height: 140)
                .blur(radius: 20)

            // Background Ring (Dim)
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: 11)
                .frame(width: 100, height: 100)

            // Progress Arc (Solid Tint)
            // Follows the total session progress (Counter-Clockwise)
            Circle()
                .trim(from: 0, to: max(0.001, (totalAngle / 360.0).truncatingRemainder(dividingBy: 1.0) == 0 && totalAngle != 0 ? 1.0 : (totalAngle / 360.0).truncatingRemainder(dividingBy: 1.0)))
                .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90)) // Start from 12 o'clock
                .animation(isRunning ? .linear(duration: 1.0) : .smooth, value: minuteAngle)
                .shadow(color: tint.opacity(0.3), radius: 6, x: 0, y: 0)

            // Hour hand (White, shorter) - Represents total session progress
            Capsule()
                .fill(Color.white)
                .frame(width: 8, height: 24)
                .offset(y: -12) // Pivot point at bottom
                .rotationEffect(.degrees(totalAngle))
                .animation(isRunning ? .linear(duration: 1.0) : .smooth, value: totalAngle)
                .shadow(color: Color.black.opacity(0.2), radius: 4)

            // Minute hand (White, longer, sharp) - Represents seconds in the current minute
            Capsule()
                .fill(Color.white)
                .frame(width: 8, height: 38)
                .offset(y: -19) // Pivot point at bottom
                .rotationEffect(.degrees(minuteAngle))
                .animation(isRunning ? .linear(duration: 1.0) : .smooth, value: minuteAngle)
                .shadow(color: Color.white.opacity(0.4), radius: 8, x: 0, y: 0)

            // Center Pivot Dot (Tinted to match the ring)
            Circle()
                .fill(tint)
                .frame(width: 14, height: 14)
                .shadow(color: tint.opacity(0.6), radius: 8, x: 0, y: 0)
        }
        .frame(width: 132, height: 132)
    }
}

private struct PomodoroTimerText: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let tint: Color
    var date: Date = .now

    var body: some View {
        Text(pomodoro.remainingText(at: date))
            .font(.system(size: PomodoroPanelMetrics.timerFontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText())
            .shadow(color: tint.opacity(0.32), radius: 16, x: 0, y: 0) // Increased glow
            .shadow(color: tint.opacity(0.12), radius: 32, x: 0, y: 0)
    }
}
