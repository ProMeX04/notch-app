import SwiftUI
struct PomodoroPanelView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @State private var idleEditorPhase: PomodoroPhase = .focus

    private var displayedPhase: PomodoroPhase {
        pomodoro.hasActiveSession ? pomodoro.phase : idleEditorPhase
    }

    private var idleDisplayedSeconds: Int {
        switch idleEditorPhase {
        case .focus:
            return pomodoro.focusMinutes * 60
        case .shortBreak:
            return pomodoro.breakMinutes * 60
        }
    }

    private var displayedTint: Color {
        Color(nsColor: displayedPhase.accentColor).ensureMinimumBrightness(factor: 0.72)
    }

    private var pomodoroClockContent: AnyView {
        if pomodoro.hasActiveSession {
            return AnyView(
                FocusClockSlot(yOffset: -2) {
                    PomodoroTimeText(
                        pomodoro: pomodoro,
                        size: 48,
                        weight: .bold
                    )
                    .foregroundStyle(.white)
                }
            )
        } else {
            return AnyView(
                FocusClockSlot(yOffset: -2) {
                    StaticTimeText(
                        seconds: idleDisplayedSeconds,
                        size: 48,
                        weight: .bold
                    )
                    .foregroundStyle(.white)
                }
            )
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FocusClockControl(
                tint: displayedTint,
                showsAdjusters: !pomodoro.hasActiveSession,
                clockAction: nil,
                onDecrease: { adjustIdleDuration(by: -1) },
                onIncrease: { adjustIdleDuration(by: 1) }
            ) {
                pomodoroClockContent
            }

            Spacer(minLength: 10)

            Group {
                if pomodoro.hasActiveSession {
                    PomodoroStreakBadge(days: learningStats.streakDays)
                } else {
                    PomodoroEditModeSwitcher(selection: $idleEditorPhase)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                HoverButton(
                    icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                    scale: .large
                ) {
                    if !pomodoro.hasActiveSession {
                        idleEditorPhase = .focus
                    }
                    pomodoro.toggleRunning()
                }
                if pomodoro.hasActiveSession {
                    HoverButton(icon: "backward.end.fill", scale: .medium) {
                        pomodoro.reset()
                    }
                    HoverButton(icon: "forward.fill", scale: .medium) {
                        pomodoro.skipPhase()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .leading)
        .onChange(of: pomodoro.hasActiveSession) { _, hasActiveSession in
            if !hasActiveSession {
                idleEditorPhase = .focus
            }
        }
    }

    private func adjustIdleDuration(by direction: Int) {
        guard !pomodoro.hasActiveSession else { return }

        switch idleEditorPhase {
        case .focus:
            pomodoro.updateCurrentDurations(
                focusMinutes: pomodoro.focusMinutes + (direction * 5),
                breakMinutes: pomodoro.breakMinutes
            )
        case .shortBreak:
            pomodoro.updateCurrentDurations(
                focusMinutes: pomodoro.focusMinutes,
                breakMinutes: pomodoro.breakMinutes + direction
            )
        }
    }
}

struct CountdownPanelView: View {
    @ObservedObject var countdown: CountdownViewModel
    private let accentColor = Color(nsColor: .systemTeal)

    private var stepSeconds: Int {
        let s = countdown.presetSeconds
        if s < 5 * 60 { return 60 }
        if s < 3600  { return 5 * 60 }
        return 15 * 60
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FocusClockControl(
                tint: accentColor.ensureMinimumBrightness(factor: 0.72),
                showsAdjusters: !countdown.hasActiveSession,
                clockAction: nil,
                onDecrease: { countdown.selectPreset(countdown.presetSeconds - stepSeconds) },
                onIncrease: { countdown.selectPreset(countdown.presetSeconds + stepSeconds) }
            ) {
                FocusClockSlot(yOffset: -2) {
                    CountdownTimeText(
                        countdown: countdown,
                        size: 48,
                        weight: .bold
                    )
                    .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 10)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                HoverButton(
                    icon: countdown.isRunning ? "pause.fill" : "play.fill",
                    scale: .large
                ) {
                    countdown.toggleRunning()
                }
                if countdown.hasActiveSession {
                    HoverButton(icon: "backward.end.fill", scale: .medium) {
                        countdown.reset()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .leading)
    }
}



struct PomodoroIconView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let displayedPhase: PomodoroPhase

    private var accentColor: Color {
        Color(nsColor: displayedPhase.accentColor).ensureMinimumBrightness(factor: 0.72)
    }

    var body: some View {
        ZStack {
            if pomodoro.isRunning {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accentColor.opacity(0.3))
                    .scaleEffect(1.08)
                    .blur(radius: 16)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            VStack(spacing: 5) {
                Image(systemName: displayedPhase.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .padding(10)
        }
        .frame(width: 56, height: 56)
    }
}

struct CountdownIconView: View {
    @ObservedObject var countdown: CountdownViewModel
    private let accentColor = Color(nsColor: .systemTeal)

    var body: some View {
        ZStack {
            if countdown.isRunning {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accentColor.opacity(0.3))
                    .scaleEffect(1.08)
                    .blur(radius: 16)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            Image(systemName: "hourglass")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
        }
        .frame(width: 56, height: 56)
    }
}

struct PomodoroTimeText: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        TimelineView(PeriodicTimelineSchedule(from: .now, by: 1.0)) { context in
            content(for: context.date)
        }
    }

    @ViewBuilder
    private func content(for date: Date) -> some View {
        let components = PomodoroTimeComponents(seconds: pomodoro.remainingSeconds(at: date))

        HStack(spacing: size <= 14 ? 1 : 3) {
            PomodoroDigitColumn(
                digit: components.minuteTens,
                size: size,
                weight: weight
            )
            PomodoroDigitColumn(
                digit: components.minuteOnes,
                size: size,
                weight: weight
            )

            Text(":")
                .font(.system(size: size, weight: weight, design: .rounded))
                .offset(y: size <= 14 ? -0.5 : -1)

            PomodoroDigitColumn(
                digit: components.secondTens,
                size: size,
                weight: weight
            )
            PomodoroDigitColumn(
                digit: components.secondOnes,
                size: size,
                weight: weight
            )
        }
    }
}

struct CountdownTimeText: View {
    @ObservedObject var countdown: CountdownViewModel
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        TimelineView(PeriodicTimelineSchedule(from: .now, by: 1.0)) { context in
            content(for: context.date)
        }
    }

    @ViewBuilder
    private func content(for date: Date) -> some View {
        ClockDigitsRow(
            components: PomodoroTimeComponents(seconds: countdown.remainingSeconds(at: date)),
            size: size,
            weight: weight
        )
    }
}

struct StaticTimeText: View {
    let seconds: Int
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        ClockDigitsRow(
            components: PomodoroTimeComponents(seconds: seconds),
            size: size,
            weight: weight
        )
    }
}

struct ClockDigitsRow: View {
    let components: PomodoroTimeComponents
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        HStack(spacing: size <= 14 ? 1 : 3) {
            PomodoroDigitColumn(
                digit: components.minuteTens,
                size: size,
                weight: weight
            )
            PomodoroDigitColumn(
                digit: components.minuteOnes,
                size: size,
                weight: weight
            )

            Text(":")
                .font(.system(size: size, weight: weight, design: .rounded))
                .offset(y: size <= 14 ? -0.5 : -1)

            PomodoroDigitColumn(
                digit: components.secondTens,
                size: size,
                weight: weight
            )
            PomodoroDigitColumn(
                digit: components.secondOnes,
                size: size,
                weight: weight
            )
        }
    }
}

struct PomodoroTimeComponents {
    let minuteTens: Int
    let minuteOnes: Int
    let secondTens: Int
    let secondOnes: Int

    init(seconds: Int) {
        let clampedSeconds = max(seconds, 0)
        let minutes = min((clampedSeconds / 60), 99)
        let seconds = clampedSeconds % 60

        minuteTens = (minutes / 10) % 10
        minuteOnes = minutes % 10
        secondTens = (seconds / 10) % 10
        secondOnes = seconds % 10
    }
}

struct FocusClockSlot<Content: View>: View {
    private let content: Content
    private let yOffset: CGFloat

    init(yOffset: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.yOffset = yOffset
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: 152, height: 50, alignment: .leading)
            .frame(width: 152, height: 62, alignment: .center)
            .offset(y: yOffset)
    }
}

struct FocusClockControl<ClockContent: View>: View {
    let tint: Color
    let showsAdjusters: Bool
    let clockAction: (() -> Void)?
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    private let clockContent: ClockContent

    init(
        tint: Color,
        showsAdjusters: Bool,
        clockAction: (() -> Void)? = nil,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        @ViewBuilder clock: () -> ClockContent
    ) {
        self.tint = tint
        self.showsAdjusters = showsAdjusters
        self.clockAction = clockAction
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.clockContent = clock()
    }

    var body: some View {
        HStack(spacing: 8) {
            FocusClockAdjustButton(
                icon: "minus",
                tint: tint,
                isVisible: showsAdjusters,
                action: onDecrease
            )

            FocusClockFace(
                action: clockAction,
                content: clockContent
            )

            FocusClockAdjustButton(
                icon: "plus",
                tint: tint,
                isVisible: showsAdjusters,
                action: onIncrease
            )
        }
        .frame(width: 204, height: 62, alignment: .leading)
    }
}

struct FocusClockFace<Content: View>: View {
    let action: (() -> Void)?
    let content: Content

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}

struct FocusClockAdjustButton: View {
    let icon: String
    let tint: Color
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isVisible {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(tint.opacity(0.18))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 22, height: 22)
            }
        }
    }
}

struct PomodoroEditModeSwitcher: View {
    @Binding var selection: PomodoroPhase

    var body: some View {
        HStack(spacing: 2) {
            phaseButton(title: "Focus", phase: .focus)
            phaseButton(title: "Break", phase: .shortBreak)
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func phaseButton(title: String, phase: PomodoroPhase) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                selection = phase
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(selection == phase ? Color.white.opacity(0.1) : Color.white.opacity(0.001))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == phase ? .white : .white.opacity(0.55))
    }
}

struct FocusClockColumn<ClockContent: View, Accessory: View>: View {
    private let clock: ClockContent
    private let accessory: Accessory

    init(
        @ViewBuilder clock: () -> ClockContent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.clock = clock()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            clock

            accessory
                .frame(width: 124, height: 18, alignment: .center)
        }
        .frame(width: 124, height: 78, alignment: .topLeading)
    }
}

struct PomodoroDigitColumn: View {
    let digit: Int
    let size: CGFloat
    let weight: Font.Weight

    private var digitHeight: CGFloat {
        size * (size <= 14 ? 1.05 : 0.98)
    }

    private var digitWidth: CGFloat {
        size * (size <= 14 ? 0.62 : 0.64)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { value in
                Text("\(value)")
                    .font(.system(size: size, weight: weight, design: .rounded))
                    .monospacedDigit()
                    .frame(width: digitWidth, height: digitHeight)
            }
        }
        .offset(y: -CGFloat(digit) * digitHeight)
        .frame(width: digitWidth, height: digitHeight, alignment: .top)
        .clipped()
        .animation(.smooth(duration: 0.28), value: digit)
    }
}

struct PomodoroPresetSelectorView: View {
    @ObservedObject var pomodoro: PomodoroViewModel

    var body: some View {
        HStack(spacing: 6) {
            InlineTimeAdjuster(
                label: "Focus",
                value: pomodoro.focusMinutes,
                tint: .orange,
                range: 5...180,
                step: 5
            ) { newFocusMinutes in
                pomodoro.updateCurrentDurations(
                    focusMinutes: newFocusMinutes,
                    breakMinutes: pomodoro.breakMinutes
                )
            }

            InlineTimeAdjuster(
                label: "Break",
                value: pomodoro.breakMinutes,
                tint: .green,
                range: 1...60,
                step: 1
            ) { newBreakMinutes in
                pomodoro.updateCurrentDurations(
                    focusMinutes: pomodoro.focusMinutes,
                    breakMinutes: newBreakMinutes
                )
            }
        }
        .frame(width: 124, alignment: .leading)
    }
}

struct CountdownPresetSelectorView: View {
    @ObservedObject var countdown: CountdownViewModel

    var body: some View {
        InlineTimeAdjuster(
            label: "Timer",
            value: countdown.presetSeconds / 60,
            tint: .teal,
            range: 1...10080, // up to 7 days in minutes
            step: 5
        ) { newMinutes in
            countdown.selectPreset(newMinutes * 60)
        }
        .frame(width: 124, alignment: .leading)
    }
}

struct InlineTimeAdjuster: View {
    let label: String
    let value: Int
    let tint: Color
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            inlineButton(icon: "minus") {
                onChange(max(range.lowerBound, value - step))
            }

            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(minWidth: 20)

            inlineButton(icon: "plus") {
                onChange(min(range.upperBound, value + step))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.2), lineWidth: 1)
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private func inlineButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(tint.opacity(0.18))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PresetValueControl: View {
    let label: String
    let value: Int
    let suffix: String
    let tint: Color
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            valueButton(icon: "minus") {
                onChange(max(range.lowerBound, value - step))
            }

            Text("\(value)\(suffix)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(minWidth: 42)

            valueButton(icon: "plus") {
                onChange(min(range.upperBound, value + step))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private func valueButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(tint.opacity(0.18))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FocusToolSwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel

    var body: some View {
        HStack(spacing: 2) {
            focusToolButton(title: "Pomodoro", icon: "timer", tool: .pomodoro)
            focusToolButton(title: "Countdown", icon: "hourglass", tool: .countdown)
            focusToolButton(title: "Stopwatch", icon: "stopwatch.fill", tool: .counter)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func focusToolButton(title: String, icon: String, tool: FocusTool) -> some View {
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                presentationModel.selectedFocusTool = tool
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(presentationModel.selectedFocusTool == tool ? Color.white.opacity(0.1) : Color.white.opacity(0.001))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(presentationModel.selectedFocusTool == tool ? .white : .white.opacity(0.5))
    }
}

struct PomodoroStreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)

            Text(days > 0 ? "\(days)d" : "0d")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(days > 0 ? 0.78 : 0.42))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct CounterPanelView: View {
    @ObservedObject var counter: CounterViewModel

    private let accentColor = Color(nsColor: .systemCyan)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FocusClockControl(
                tint: accentColor.ensureMinimumBrightness(factor: 0.72),
                showsAdjusters: false,
                clockAction: nil,
                onDecrease: {},
                onIncrease: {}
            ) {
                FocusClockSlot(yOffset: -2) {
                    StopwatchTimeText(
                        counter: counter,
                        size: 48,
                        weight: .bold
                    )
                    .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                HoverButton(
                    icon: counter.isRunning ? "pause.fill" : "play.fill",
                    scale: .large
                ) {
                    counter.toggleRunning()
                }
                if counter.hasActiveSession {
                    HoverButton(icon: "backward.end.fill", scale: .medium) {
                        counter.reset()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .leading)
    }
}

struct CounterIconView: View {
    @ObservedObject var counter: CounterViewModel

    private let accentColor = Color(nsColor: .systemCyan)

    var body: some View {
        ZStack {
            if counter.isRunning {
                RoundedRectangle(cornerRadius: 16)
                    .fill(accentColor.opacity(0.3))
                    .scaleEffect(1.08)
                    .blur(radius: 16)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }

            Image(systemName: "stopwatch.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
        }
        .frame(width: 56, height: 56)
    }
}

struct StopwatchTimeText: View {
    @ObservedObject var counter: CounterViewModel
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        TimelineView(PeriodicTimelineSchedule(from: .now, by: 1.0)) { context in
            content(for: context.date)
        }
    }

    @ViewBuilder
    private func content(for date: Date) -> some View {
        let total = counter.elapsedSeconds(at: date)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        HStack(spacing: size <= 14 ? 1 : 3) {
            if hours > 0 {
                PomodoroDigitColumn(digit: (hours / 10) % 10, size: size, weight: weight)
                PomodoroDigitColumn(digit: hours % 10, size: size, weight: weight)

                Text(":")
                    .font(.system(size: size, weight: weight, design: .rounded))
                    .offset(y: size <= 14 ? -0.5 : -1)
            }

            PomodoroDigitColumn(digit: (minutes / 10) % 10, size: size, weight: weight)
            PomodoroDigitColumn(digit: minutes % 10, size: size, weight: weight)

            Text(":")
                .font(.system(size: size, weight: weight, design: .rounded))
                .offset(y: size <= 14 ? -0.5 : -1)

            PomodoroDigitColumn(digit: (seconds / 10) % 10, size: size, weight: weight)
            PomodoroDigitColumn(digit: seconds % 10, size: size, weight: weight)
        }
    }
}

struct CompactCounterView: View {
    @ObservedObject var counter: CounterViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
    }

    private let accentColor = Color(nsColor: .systemCyan)

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor.gradient)

                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .overlay {
                    HStack {
                        Spacer(minLength: 0)

                        StopwatchTimeText(
                            counter: counter,
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
                    .fill(accentColor.opacity(counter.isRunning ? 0.18 : 0.1))

                Image(systemName: counter.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accentColor.ensureMinimumBrightness(factor: 0.72))
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}
