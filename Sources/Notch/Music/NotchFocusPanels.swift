import SwiftUI
import Charts
import NotchFocusCore

private enum FocusMetrics {
    static let clockHeight: CGFloat = 84
    static let iconButtonSize: CGFloat = 56
    static let columnWidth: CGFloat = 124
    static let columnHeight: CGFloat = 78
    static let clockFontSize: CGFloat = 78
}

struct PomodoroPanelView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isShowingSettings: Bool = false
    @State private var isShowingStats: Bool = false
    @State private var isShowingResetConfirmation: Bool = false
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var showsOverlayPanel: Bool {
        isShowingSettings || isShowingStats
    }

    private var displayedTint: Color {
        pomodoro.phase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.72)
    }

    private var interfaceTint: Color {
        NotchAccentColorOption.resolve(rawValue: accentColorID).color.ensureMinimumBrightness(factor: 0.78)
    }

    private var dockState: PomodoroPanelDock.State {
        if pomodoro.isRunning {
            return .running
        }
        return pomodoro.hasActiveSession ? .paused : .idle
    }

    var body: some View {
        VStack {
            if isShowingSettings {
                PomodoroQuickSettingsView(pomodoro: pomodoro, isPresented: $isShowingSettings, tint: interfaceTint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isShowingStats {
                PomodoroStatsView(learningStats: learningStats, isPresented: $isShowingStats, tint: interfaceTint)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: PomodoroPanelMetrics.contentSpacing) {
                    PomodoroPanelHeader(pomodoro: pomodoro, tint: displayedTint)

                    PomodoroPanelTimer(pomodoro: pomodoro, tint: displayedTint)

                    PomodoroPanelTaskChip(pomodoro: pomodoro, tint: displayedTint)

                    PomodoroPanelDock(
                        state: dockState,
                        phaseTint: displayedTint,
                        interfaceTint: interfaceTint,
                        onPrimaryAction: {
                            pomodoro.toggleRunning()
                        },
                        onReset: {
                            if pomodoro.hasActiveSession {
                                isShowingResetConfirmation = true
                            } else {
                                pomodoro.reset()
                            }
                        },
                        onStats: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                isShowingStats = true
                            }
                        },
                        onSettings: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                isShowingSettings = true
                            }
                        },
                        onSkip: {
                            pomodoro.skipPhase()
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, PomodoroPanelMetrics.horizontalPadding)
        .padding(.vertical, PomodoroPanelMetrics.verticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: isShowingSettings ? 160 : 120,
            maxHeight: isShowingSettings ? 340 : (isShowingStats ? 175 : 210),
            alignment: .center
        )
        .background(showsOverlayPanel ? Color.black : Color.clear)
        .foregroundStyle(.white)
        .onAppear {
            presentationModel.isFocusOverlayPresented = showsOverlayPanel
        }
        .onChange(of: showsOverlayPanel) { _, isPresented in
            presentationModel.isFocusOverlayPresented = isPresented
        }
        .onDisappear {
            presentationModel.isFocusOverlayPresented = false
        }
        .alert(Localization.get("Reset", lang: appLanguage), isPresented: $isShowingResetConfirmation) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {}
            Button(Localization.get("Reset", lang: appLanguage), role: .destructive) {
                pomodoro.reset()
            }
        } message: {
            Text(Localization.get("Current focus session will be cleared. Continue?", lang: appLanguage))
        }
    }
}

struct PomodoroIconView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let displayedPhase: PomodoroPhase

    private var accentColor: Color {
        displayedPhase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.72)
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
        .frame(width: FocusMetrics.iconButtonSize, height: FocusMetrics.iconButtonSize)
    }
}

struct PomodoroTimeText: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(pomodoro.remainingText(at: context.date))
                .font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct StaticTimeText: View {
    let seconds: Int
    let size: CGFloat
    let weight: Font.Weight

    var body: some View {
        let minutes = seconds / 60
        let secs = seconds % 60
        let text = String(format: "%02d:%02d", minutes, secs)
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
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
            .frame(height: FocusMetrics.clockHeight, alignment: .center)
            .offset(y: yOffset)
    }
}

struct FocusClockFace<Content: View>: View {
    let action: (() -> Void)?
    private let content: Content

    init(action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

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
                .frame(width: FocusMetrics.columnWidth, height: 18, alignment: .center)
        }
        .frame(width: FocusMetrics.columnWidth, height: FocusMetrics.columnHeight, alignment: .topLeading)
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
        .frame(width: FocusMetrics.columnWidth, alignment: .leading)
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

// Standardized globally via StandardUI.swift

struct PomodoroQuickSettingsView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @Binding var isPresented: Bool
    let tint: Color
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(SoundManager.focusTransitionSoundKey) private var focusTransitionSoundID: String = FocusTransitionSoundOption.defaultOption.rawValue

    private var selectedFocusTransitionSound: FocusTransitionSoundOption {
        FocusTransitionSoundOption(rawValue: focusTransitionSoundID) ?? .defaultOption
    }

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ], spacing: 6) {
                        settingInput(label: "Focus", value: pomodoro.focusMinutes) {
                            pomodoro.updateCurrentDurations(focusMinutes: $0, breakMinutes: pomodoro.breakMinutes)
                        }
                        settingInput(label: "Short", value: pomodoro.breakMinutes) {
                            pomodoro.updateCurrentDurations(focusMinutes: pomodoro.focusMinutes, breakMinutes: $0)
                        }
                        settingInput(label: "Cycle", value: pomodoro.sessionsBeforeLongBreak, range: 1...12) {
                            pomodoro.updateSessionsBeforeLongBreak(count: $0)
                        }
                        settingInput(label: "Long", value: pomodoro.longBreakDurationSeconds / 60) {
                            pomodoro.updateLongBreakDuration(minutes: $0)
                        }
                        settingToggle(label: "Auto Breaks", isOn: $pomodoro.autoStartBreaks)
                        settingToggle(label: "Auto Pomo", isOn: $pomodoro.autoStartPomodoros)
                    }

                    Menu {
                        ForEach(FocusTransitionSoundOption.allCases, id: \.self) { sound in
                            Button(Localization.get(sound.displayName, lang: appLanguage)) {
                                focusTransitionSoundID = sound.rawValue
                                SoundManager.previewFocusTransitionSound(sound)
                            }
                        }
                    } label: {
                        NotchMenuFieldRow(
                            leadingIcon: "speaker.fill",
                            title: "\(Localization.get("Sound", lang: appLanguage)): \(Localization.get(selectedFocusTransitionSound.displayName, lang: appLanguage))"
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: 232)

            HStack {
                Spacer(minLength: 0)

                compactDoneButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(settingsCardBackground())
    }

    private func settingToggle(label: String, isOn: Binding<Bool>) -> some View {
        let isEnabled = isOn.wrappedValue

        return HStack(spacing: 4) {
            Text(Localization.get(label, lang: appLanguage))
                .font(NotchPanelFieldMetrics.labelFont)
                .foregroundStyle(isEnabled ? .white.opacity(0.96) : .white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(NotchSwitchStyle(tint: tint))
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(maxWidth: .infinity, minHeight: StandardButtonMetrics.height, alignment: .center)
        .background(settingCellBackground(stroke: isEnabled ? Color.white.opacity(0.16) : NotchPanelFieldMetrics.fieldStroke))
    }

    private func settingInput(label: String, value: Int, range: ClosedRange<Int> = 1...180, action: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            Text(Localization.get(label, lang: appLanguage))
                .font(NotchPanelFieldMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", value: Binding(
                get: { value },
                set: { newValue in
                    let clamped = max(range.lowerBound, min(newValue, range.upperBound))
                    action(clamped)
                }
            ), format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(NotchPanelFieldMetrics.labelFont)
            .foregroundStyle(tint)
            .frame(width: 28)
            .offset(y: 0.5)
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(maxWidth: .infinity, minHeight: StandardButtonMetrics.height, alignment: .leading)
        .background(settingCellBackground(stroke: NotchPanelFieldMetrics.fieldStroke))
    }

    private func settingButton(label: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(Localization.get(label, lang: appLanguage))
                    .font(NotchPanelFieldMetrics.labelFont)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 9, weight: .bold))
                    Text(value).font(NotchPanelFieldMetrics.labelFont)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, NotchPanelFieldMetrics.hPad)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, NotchPanelFieldMetrics.hPad)
            .padding(.vertical, NotchPanelFieldMetrics.vPad)
            .frame(maxWidth: .infinity, minHeight: StandardButtonMetrics.height, alignment: .leading)
            .background(settingCellBackground(stroke: NotchPanelFieldMetrics.fieldStroke))
        }
        .buttonStyle(.plain)
    }

    private var compactDoneButton: some View {
        StandardActionButton(
            title: Localization.get("Done", lang: appLanguage),
            tint: tint,
            variant: .primary
        ) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isPresented = false
            }
        }
    }

    private func settingsCardBackground() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }

    private func settingCellBackground(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
            .fill(NotchPanelFieldMetrics.fieldFill)
            .overlay {
                RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
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
            let localizedDay = Localization.get(selectedDay, lang: appLanguage)
            if appLanguage == "Tiếng Việt" {
                return localizedDay
            }
            return "\(Localization.get("Focus on", lang: appLanguage)) \(localizedDay)"
        }
        return Localization.get("Last 7 Days", lang: appLanguage)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayedLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 4)
                Text(learningStats.formattedDuration(displayedSeconds))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
                
                StandardActionButton(
                    title: Localization.get("Done", lang: appLanguage),
                    icon: "checkmark",
                    tint: tint,
                    variant: .primary
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }
            }
            .frame(width: 120, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(statsCardBackground(stroke: Color.white.opacity(0.08)))
            
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
                                .foregroundStyle(.white.opacity(0.84))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(statsCardBackground(stroke: Color.white.opacity(0.08)))
        }
        .padding(.horizontal, 10)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private func statsCardBackground(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}


// PomodoroSessionDotsView moved to its own file in Focus directory
