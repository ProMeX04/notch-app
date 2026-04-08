import SwiftUI
import Charts
struct PomodoroPanelView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @State private var idleEditorPhase: PomodoroPhase = .focus
    @State private var isShowingSettings: Bool = false
    @State private var isShowingStats: Bool = false
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var displayedPhase: PomodoroPhase {
        pomodoro.hasActiveSession ? pomodoro.phase : idleEditorPhase
    }

    private var idleDisplayedSeconds: Int {
        switch idleEditorPhase {
        case .focus:
            return pomodoro.focusDurationSeconds
        case .shortBreak:
            return pomodoro.breakDurationSeconds
        case .longBreak:
            return pomodoro.longBreakDurationSeconds
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
                        size: 78,
                        weight: .bold
                    )
                    .foregroundStyle(displayedTint)
                }
            )
        } else {
            return AnyView(
                FocusClockSlot(yOffset: -2) {
                    StaticTimeText(
                        seconds: idleDisplayedSeconds,
                        size: 78,
                        weight: .bold
                    )
                    .foregroundStyle(displayedTint)
                }
            )
        }
    }

    var body: some View {
        VStack {
            if isShowingSettings {
                PomodoroQuickSettingsView(pomodoro: pomodoro, isPresented: $isShowingSettings, tint: displayedTint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isShowingStats {
                PomodoroStatsView(learningStats: learningStats, isPresented: $isShowingStats, tint: displayedTint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ZStack {
                    // Center area
                    VStack(spacing: 8) {
                        Text(Localization.get(displayedPhase.rawValue, lang: appLanguage))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(displayedTint.opacity(0.12))
                            )
                            .foregroundStyle(displayedTint)
                            .onTapGesture {
                                withAnimation(.smooth(duration: 0.22)) {
                                    let phases: [PomodoroPhase] = [.focus, .shortBreak, .longBreak]
                                    let currentIndex = phases.firstIndex(of: displayedPhase) ?? 0
                                    let nextPhase = phases[(currentIndex + 1) % phases.count]
                                    
                                    if pomodoro.hasActiveSession {
                                        pomodoro.setPhase(nextPhase)
                                    } else {
                                        idleEditorPhase = nextPhase
                                    }
                                }
                            }

                        if pomodoro.hasActiveSession {
                            HStack(spacing: 8) {
                                PomodoroSessionDotsView(
                                    current: pomodoro.completedSessionsInCycle,
                                    total: pomodoro.sessionsBeforeLongBreak,
                                    isFocus: pomodoro.phase == .focus,
                                    tint: displayedTint
                                )
                                
                                Text("\(Localization.get("Round", lang: appLanguage)) \(pomodoro.currentFocusSessionIndex)/\(pomodoro.sessionsBeforeLongBreak)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(displayedTint.opacity(0.85))
                            }
                            .padding(.top, -2)
                        }

                        FocusClockControl(
                            tint: displayedTint,
                            showsAdjusters: false,
                            clockAction: nil,
                            onDecrease: { },
                            onIncrease: { }
                        ) {
                            pomodoroClockContent
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(true)

                    // Left overlay
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    isShowingStats = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(Localization.get("Stats", lang: appLanguage))
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(displayedTint)
                                .padding(.leading, 10)
                                .frame(width: 95, height: 26, alignment: .leading)
                                .background(Capsule().fill(displayedTint.opacity(0.15)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    isShowingSettings = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(Localization.get("Settings", lang: appLanguage))
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(displayedTint)
                                .padding(.leading, 10)
                                .frame(width: 95, height: 26, alignment: .leading)
                                .background(Capsule().fill(displayedTint.opacity(0.15)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(true)

                    // Right overlay
                    HStack(spacing: 8) {
                        Spacer()
                        VStack(spacing: 8) {
                            if pomodoro.isRunning {
                                FocusPanelActionButton(
                                    title: Localization.get("Skip", lang: appLanguage),
                                    tint: displayedTint
                                ) {
                                    pomodoro.skipPhase()
                                }
                            }
                            
                            FocusPanelActionButton(
                                title: Localization.get(pomodoro.isRunning ? "Pause" : "Start", lang: appLanguage),
                                tint: displayedTint
                            ) {
                                pomodoro.toggleRunning()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(true)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: (isShowingSettings || isShowingStats) ? 175 : 115, alignment: .center)
        .padding(.horizontal, 20)
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
        case .longBreak:
            let currentLongBreakMinutes = pomodoro.longBreakDurationSeconds / 60
            pomodoro.updateLongBreakDuration(minutes: currentLongBreakMinutes + (direction * 5))
        }
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
            .frame(height: 84, alignment: .center)
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
        .frame(height: 84, alignment: .center)
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.12))
                        )
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 32, height: 32)
            }
        }
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
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(.white.opacity(0.12))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
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
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(.white.opacity(0.12))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

struct FocusPanelActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint == .white ? .black : .white)
                .frame(width: 95, height: 26)
                .background(
                    Capsule()
                        .fill(tint == .white ? Color.white : tint)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PomodoroQuickSettingsView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @Binding var isPresented: Bool
    let tint: Color
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        HStack(spacing: 24) {
            // First Column: 3 settings rows
            VStack(alignment: .leading, spacing: 10) {
                settingInput(label: "Focus", value: pomodoro.focusMinutes) { 
                    pomodoro.updateCurrentDurations(focusMinutes: $0, breakMinutes: pomodoro.breakMinutes) 
                }
                settingInput(label: "Short", value: pomodoro.breakMinutes) { 
                    pomodoro.updateCurrentDurations(focusMinutes: pomodoro.focusMinutes, breakMinutes: $0) 
                }
                settingInput(label: "Long", value: pomodoro.longBreakDurationSeconds / 60) { 
                    pomodoro.updateLongBreakDuration(minutes: $0) 
                }
                settingInput(label: "Cycle", value: pomodoro.sessionsBeforeLongBreak, range: 1...12) {
                    pomodoro.updateSessionsBeforeLongBreak(count: $0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Second Column: Toggles and Done
            VStack(alignment: .trailing, spacing: 12) {
                settingToggle(label: "Auto-start Breaks", isOn: $pomodoro.autoStartBreaks)
                
                settingToggle(label: "Auto-start Pomo", isOn: $pomodoro.autoStartPomodoros)
                
                Spacer(minLength: 0)
                
                FocusPanelActionButton(
                    title: Localization.get("Done", lang: appLanguage),
                    tint: tint
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }
            }
            .frame(width: 220, alignment: .trailing)
        }
    }

    private func settingToggle(label: String, isOn: Binding<Bool>) -> some View {
        let isEnabled = isOn.wrappedValue

        return HStack(spacing: 10) {
            Text(Localization.get(label, lang: appLanguage))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(NotchSwitchStyle(tint: tint))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isEnabled ? Color.white.opacity(0.08) : Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isEnabled ? tint.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func settingInput(label: String, value: Int, range: ClosedRange<Int> = 1...180, action: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(Localization.get(label, lang: appLanguage))
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(tint.opacity(0.7))
                .frame(width: 80, alignment: .leading)
                
            HStack(spacing: 10) {
                Button { action(max(range.lowerBound, value - 1)) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(tint.opacity(0.5), tint.opacity(0.1)) }.buttonStyle(.plain)
                Text("\(value)").font(.system(size: 18, weight: .bold, design: .rounded)).frame(minWidth: 26).foregroundStyle(.white)
                Button { action(min(range.upperBound, value + 1)) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(tint.opacity(0.5), tint.opacity(0.1)) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}


// MARK: - Stats View

struct DayStats: Identifiable {
    let id = UUID()
    let date: Date
    let seconds: Int
    
    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct PomodoroStatsView: View {
    @ObservedObject var learningStats: LearningStatsStore
    @Binding var isPresented: Bool
    let tint: Color
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var selectedDay: String? = nil
    
    private var chartData: [DayStats] {
        let calendar = Calendar.current
        var result: [DayStats] = []
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: .now))!
            let daySeconds = learningStats.entries.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.reduce(0) { $0 + $1.seconds }
            result.append(DayStats(date: date, seconds: daySeconds))
        }
        return result.reversed()
    }
    
    private var totalSeconds: Int {
        chartData.reduce(0) { $0 + $1.seconds }
    }
    
    private var displayedSeconds: Int {
        if let selectedDay, let data = chartData.first(where: { $0.dayLabel == selectedDay }) {
            return data.seconds
        }
        return totalSeconds
    }
    
    private var displayedLabel: String {
        if let selectedDay {
             return "\(Localization.get("Focus on", lang: appLanguage)) \(selectedDay)"
        }
        return Localization.get("Last 7 Days", lang: appLanguage)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayedLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
                Text(learningStats.formattedDuration(displayedSeconds))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                } label: {
                    Text(Localization.get("Done", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.blue)
            }
            .frame(width: 120, alignment: .leading)
            
            Chart(chartData) { day in
                BarMark(
                    x: .value("Day", day.dayLabel),
                    y: .value("Minutes", Double(day.seconds) / 60.0)
                )
                .foregroundStyle(tint.gradient)
                .opacity(selectedDay == nil || selectedDay == day.dayLabel ? 1.0 : 0.4)
                .cornerRadius(4)
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: chartData.map { $0.dayLabel }) { value in
                    AxisValueLabel() {
                        if let label = value.as(String.self) {
                            Text(Localization.get(label, lang: appLanguage))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }
}

struct PomodoroSessionDotsView: View {
    let current: Int
    let total: Int
    let isFocus: Bool
    let tint: Color
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(fillColor(for: index))
                    .frame(width: 5, height: 5)
                    .overlay {
                        if isFocus && index == current {
                            Circle()
                                .stroke(tint.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 9, height: 9)
                        }
                    }
                    .frame(width: 9, height: 9)
            }
        }
    }
    
    private func fillColor(for index: Int) -> Color {
        if index < current {
            return tint
        } else if isFocus && index == current {
            return tint.opacity(0.3)
        } else {
            return Color.white.opacity(0.12)
        }
    }
}
