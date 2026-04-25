import SwiftUI
import NotchFocusCore

struct PomodoroPanelView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @Namespace private var timerNamespace

    private var displayedTint: Color {
        pomodoro.phase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.72)
    }

    var body: some View {
        ZStack {
            if pomodoro.isRunning {
                PomodoroActiveFocusPanel(
                    pomodoro: pomodoro,
                    tint: displayedTint,
                    namespace: timerNamespace
                )
            } else {
                PomodoroSimpleFocusPanel(
                    pomodoro: pomodoro,
                    tint: displayedTint,
                    namespace: timerNamespace
                )
            }
        }
        .padding(.horizontal, PomodoroPanelMetrics.horizontalPadding)
        .padding(.vertical, PomodoroPanelMetrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 182, alignment: .center)
        .foregroundStyle(.white)
    }
}

// PomodoroSessionDotsView moved to its own file in Focus directory
