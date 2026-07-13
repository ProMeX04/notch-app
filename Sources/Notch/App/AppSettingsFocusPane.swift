import Charts
import NotchFocusFeature
import SwiftUI

struct AppFocusSettingsPane: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    let isBackendAuthenticated: Bool
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @AppStorage(SoundManager.focusTransitionSoundKey) private var focusTransitionSoundID: String = FocusTransitionSoundOption.defaultOption.rawValue

    private var tint: Color {
        NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
    }

    private var selectedFocusTransitionSound: FocusTransitionSoundOption {
        FocusTransitionSoundOption(rawValue: focusTransitionSoundID) ?? .defaultOption
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Focus", lang: appLanguage),
                subtitle: Localization.get("Pomodoro lengths, weekly activity, and ranking privacy", lang: appLanguage)
            )

            AppSettingsCard(
                title: Localization.get("Overview", lang: appLanguage),
                subtitle: Localization.get("Last 7 days", lang: appLanguage)
            ) {
                AppFocusOverviewSection(learningStats: learningStats, tint: tint)
            }

            AppSettingsCard(
                title: Localization.get("Session", lang: appLanguage),
                subtitle: Localization.get("Lengths and long-break cycle", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    FocusDurationRow(
                        icon: "timer",
                        title: Localization.get("Focus", lang: appLanguage),
                        value: pomodoro.focusMinutes,
                        unit: Localization.get("min", lang: appLanguage),
                        range: 5...180,
                        step: 5,
                        tint: tint,
                        showDivider: true
                    ) {
                        pomodoro.updateCurrentDurations(
                            focusMinutes: $0,
                            breakMinutes: pomodoro.breakMinutes
                        )
                    }

                    FocusDurationRow(
                        icon: "cup.and.saucer.fill",
                        title: Localization.get("Short Break", lang: appLanguage),
                        value: pomodoro.breakMinutes,
                        unit: Localization.get("min", lang: appLanguage),
                        range: 1...60,
                        step: 1,
                        tint: tint,
                        showDivider: true
                    ) {
                        pomodoro.updateCurrentDurations(
                            focusMinutes: pomodoro.focusMinutes,
                            breakMinutes: $0
                        )
                    }

                    FocusDurationRow(
                        icon: "leaf.fill",
                        title: Localization.get("Long Break", lang: appLanguage),
                        value: pomodoro.longBreakDurationSeconds / 60,
                        unit: Localization.get("min", lang: appLanguage),
                        range: 1...60,
                        step: 1,
                        tint: tint,
                        showDivider: true
                    ) {
                        pomodoro.updateLongBreakDuration(minutes: $0)
                    }

                    FocusDurationRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: Localization.get("Sessions before long break", lang: appLanguage),
                        value: pomodoro.sessionsBeforeLongBreak,
                        unit: Localization.get("pomo", lang: appLanguage),
                        range: 1...12,
                        step: 1,
                        tint: tint,
                        showDivider: false
                    ) {
                        pomodoro.updateSessionsBeforeLongBreak(count: $0)
                    }

                    Text(
                        String(
                            format: Localization.get(
                                "Long break every %d focus sessions",
                                lang: appLanguage
                            ),
                            pomodoro.sessionsBeforeLongBreak
                        )
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            AppSettingsCard(
                title: Localization.get("Sound & Alerts", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    AppSettingsRow(showDivider: true) {
                        focusRowIcon("speaker.wave.2.fill")
                        Text(Localization.get("Transition Sound", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Spacer(minLength: 8)

                        NotchSegmentedPicker(
                            options: FocusTransitionSoundOption.allCases,
                            selection: Binding(
                                get: {
                                    FocusTransitionSoundOption(rawValue: focusTransitionSoundID) ?? .thoribass
                                },
                                set: { focusTransitionSoundID = $0.rawValue }
                            ),
                            titleMapper: { Localization.get($0.displayName, lang: appLanguage) },
                            tint: tint
                        )
                        .frame(width: 220)
                        .onChange(of: focusTransitionSoundID) { _, _ in
                            SoundManager.previewFocusTransitionSound(selectedFocusTransitionSound)
                        }
                    }

                    focusToggle(
                        icon: "bell.badge.fill",
                        title: Localization.get("Enable Notifications", lang: appLanguage),
                        subtitle: Localization.get("Notify when a phase ends", lang: appLanguage),
                        isOn: $pomodoro.notificationsEnabled,
                        showDivider: false
                    )
                }
            }

            AppSettingsCard(
                title: Localization.get("Automation", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    focusToggle(
                        icon: "play.circle.fill",
                        title: Localization.get("Auto Start Breaks", lang: appLanguage),
                        subtitle: Localization.get("Begin breaks when focus ends", lang: appLanguage),
                        isOn: $pomodoro.autoStartBreaks,
                        showDivider: true
                    )

                    focusToggle(
                        icon: "bolt.circle.fill",
                        title: Localization.get("Auto Start Pomo", lang: appLanguage),
                        subtitle: Localization.get("Begin focus when a break ends", lang: appLanguage),
                        isOn: $pomodoro.autoStartPomodoros,
                        showDivider: true
                    )

                    focusToggle(
                        icon: "menubar.rectangle",
                        title: Localization.get("Show Focus Timer in Menu Bar", lang: appLanguage),
                        subtitle: Localization.get("Keep the countdown visible outside Notch", lang: appLanguage),
                        isOn: $pomodoro.showMenuBarClockDuringFocus,
                        showDivider: false
                    )
                }
            }

            AppSettingsCard(
                title: Localization.get("Cloud Ranking", lang: appLanguage)
            ) {
                AppFocusCloudRankingSettingsView(
                    focusCloudSync: focusCloudSync,
                    isBackendAuthenticated: isBackendAuthenticated,
                    tint: tint
                )
            }
        }
    }

    private func focusRowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.1).cornerRadius(8))
    }

    private func focusToggle(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        showDivider: Bool
    ) -> some View {
        AppSettingsRow(showDivider: showDivider) {
            focusRowIcon(icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .toggleStyle(NotchSwitchStyle(tint: tint))
                .labelsHidden()
        }
    }
}

// MARK: - Overview

private struct AppFocusOverviewSection: View {
    @ObservedObject var learningStats: LearningStatsStore
    let tint: Color

    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var selectedDay: String?

    private var chartData: [AppFocusStatsDay] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else {
                return nil
            }
            let daySeconds = learningStats.entries
                .filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
                .reduce(0) { $0 + $1.seconds }
            return AppFocusStatsDay(date: date, seconds: daySeconds)
        }
        .reversed()
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
        guard let selectedDay else {
            return Localization.get("Selected period", lang: appLanguage)
        }
        let localizedDay = Localization.get(selectedDay, lang: appLanguage)
        if appLanguage == "Tiếng Việt" {
            return localizedDay
        }
        return "\(Localization.get("Focus on", lang: appLanguage)) \(localizedDay)"
    }

    private var hasActivity: Bool {
        totalSeconds > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                overviewMetric(
                    title: Localization.get("Today", lang: appLanguage),
                    value: learningStats.formattedDuration(learningStats.todayLearningSeconds),
                    emphasized: true
                )
                overviewMetric(
                    title: displayedLabel,
                    value: learningStats.formattedDuration(displayedSeconds),
                    emphasized: false
                )
                overviewMetric(
                    title: Localization.get("Streak", lang: appLanguage),
                    value: "\(learningStats.streakDays)d",
                    emphasized: false
                )
                overviewMetric(
                    title: Localization.get("Sessions", lang: appLanguage),
                    value: "\(learningStats.totalSessions)",
                    emphasized: false
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Localization.get("Weekly Activity", lang: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 8)
                    Text(learningStats.formattedDuration(learningStats.averageSessionSeconds))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.95))
                    Text(Localization.get("avg session", lang: appLanguage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                if hasActivity {
                    Chart(chartData) { day in
                        BarMark(
                            x: .value("Day", day.dayLabel),
                            y: .value("Minutes", Double(day.seconds) / 60.0)
                        )
                        .foregroundStyle(
                            (selectedDay == nil || selectedDay == day.dayLabel)
                                ? AnyShapeStyle(tint.gradient)
                                : AnyShapeStyle(Color.white.opacity(0.14))
                        )
                        .cornerRadius(4)
                    }
                    .chartXSelection(value: $selectedDay)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: chartData.map(\.dayLabel)) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(Localization.get(label, lang: appLanguage))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    .frame(height: 132)
                    .accessibilityLabel(Localization.get("Weekly Activity", lang: appLanguage))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.28))
                        Text(Localization.get("No focus time yet this week", lang: appLanguage))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    private func overviewMetric(title: String, value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(.system(size: emphasized ? 22 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(emphasized ? 0.98 : 0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(emphasized ? 0.06 : 0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(emphasized ? 0.1 : 0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct AppFocusStatsDay: Identifiable {
    let id = UUID()
    let date: Date
    let seconds: Int

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Duration row

private struct FocusDurationRow: View {
    let icon: String
    let title: String
    let value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    let tint: Color
    let showDivider: Bool
    let onChange: (Int) -> Void

    private var canDecrement: Bool { value > range.lowerBound }
    private var canIncrement: Bool { value < range.upperBound }

    var body: some View {
        AppSettingsRow(showDivider: showDivider) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1).cornerRadius(8))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                stepButton(systemName: "minus", enabled: canDecrement) {
                    onChange(clamped(value - step))
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField(
                        "",
                        value: Binding(
                            get: { value },
                            set: { onChange(clamped($0)) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)

                    Text(unit)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 36, alignment: .leading)
                }

                stepButton(systemName: "plus", enabled: canIncrement) {
                    onChange(clamped(value + step))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue("\(value) \(unit)")
        }
    }

    private func clamped(_ raw: Int) -> Int {
        min(max(raw, range.lowerBound), range.upperBound)
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? .white.opacity(0.88) : .white.opacity(0.28))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(enabled ? 0.10 : 0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "plus" ? "Increase" : "Decrease")
    }
}

// MARK: - Cloud ranking

private struct AppFocusCloudRankingSettingsView: View {
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    let isBackendAuthenticated: Bool
    let tint: Color

    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var isSaving = false

    var body: some View {
        AppSettingsRow(showDivider: false) {
            Image(systemName: isBackendAuthenticated ? "eye.slash.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1).cornerRadius(8))

            VStack(alignment: .leading, spacing: 3) {
                Text(Localization.get("Rank anonymously", lang: appLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(descriptionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { !focusCloudSync.leaderboardOptIn },
                set: { anonymous in
                    Task { @MainActor in
                        isSaving = true
                        await focusCloudSync.updateLeaderboardProfile(
                            optIn: !anonymous,
                            displayName: focusCloudSync.displayName
                        )
                        isSaving = false
                    }
                }
            ))
            .toggleStyle(NotchSwitchStyle(tint: tint))
            .labelsHidden()
            .disabled(!isBackendAuthenticated || isSaving)
            .opacity(isBackendAuthenticated ? 1 : 0.45)
        }
    }

    private var descriptionText: String {
        guard isBackendAuthenticated else {
            return Localization.get("Sign in from Account settings to sync focus ranking.", lang: appLanguage)
        }
        return focusCloudSync.leaderboardOptIn
            ? Localization.get("Showing your profile name on the leaderboard.", lang: appLanguage)
            : Localization.get("Ranking anonymously on the leaderboard.", lang: appLanguage)
    }
}
