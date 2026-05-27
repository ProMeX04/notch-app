import Charts
import NotchFocusFeature
import SwiftUI

struct AppFocusSettingsPane: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var websiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    let isBackendAuthenticated: Bool
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @AppStorage(SoundManager.focusTransitionSoundKey) private var focusTransitionSoundID: String = FocusTransitionSoundOption.defaultOption.rawValue

    @State private var isAutoOpenUrlsExpanded = false

    private var tint: Color {
        NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
    }

    private var selectedFocusTransitionSound: FocusTransitionSoundOption {
        FocusTransitionSoundOption(rawValue: focusTransitionSoundID) ?? .defaultOption
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Focus", lang: appLanguage)
            )

            VStack(alignment: .leading, spacing: 18) {
                AppSettingsCard(
                    title: Localization.get("Weekly Activity", lang: appLanguage)
                ) {
                    AppFocusStatsSettingsView(learningStats: learningStats, tint: tint)
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

                AppSettingsCard(
                    title: Localization.get("Session Timing", lang: appLanguage)
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        AppSettingsRow(showDivider: true) {
                            HStack(spacing: 12) {
                                durationControl(
                                    label: Localization.get("Focus", lang: appLanguage),
                                    value: pomodoro.focusMinutes,
                                    range: 5...180,
                                    tint: tint
                                ) {
                                    pomodoro.updateCurrentDurations(focusMinutes: $0, breakMinutes: pomodoro.breakMinutes)
                                }

                                durationControl(
                                    label: Localization.get("Short", lang: appLanguage),
                                    value: pomodoro.breakMinutes,
                                    range: 1...60,
                                    tint: tint
                                ) {
                                    pomodoro.updateCurrentDurations(focusMinutes: pomodoro.focusMinutes, breakMinutes: $0)
                                }

                                durationControl(
                                    label: Localization.get("Long", lang: appLanguage),
                                    value: pomodoro.longBreakDurationSeconds / 60,
                                    range: 1...60,
                                    tint: tint
                                ) {
                                    pomodoro.updateLongBreakDuration(minutes: $0)
                                }

                                durationControl(
                                    label: Localization.get("Cycle", lang: appLanguage),
                                    value: pomodoro.sessionsBeforeLongBreak,
                                    range: 1...12,
                                    suffix: "x",
                                    tint: tint
                                ) {
                                    pomodoro.updateSessionsBeforeLongBreak(count: $0)
                                }
                            }
                        }

                        AppSettingsRow(showDivider: false) {
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))

                                Text(Localization.get("Transition Sound", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))

                                Spacer()

                                NotchSegmentedPicker(
                                    options: FocusTransitionSoundOption.allCases,
                                    selection: Binding(
                                        get: { FocusTransitionSoundOption(rawValue: focusTransitionSoundID) ?? .thoribass },
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
                        }
                    }
                }

                AppSettingsCard(
                    title: Localization.get("Automation", lang: appLanguage)
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        automationToggle(
                            icon: "play.circle.fill",
                            title: Localization.get("Auto Start Breaks", lang: appLanguage),
                            isOn: $pomodoro.autoStartBreaks,
                            tint: tint,
                            showDivider: true
                        )

                        automationToggle(
                            icon: "bolt.circle.fill",
                            title: Localization.get("Auto Start Pomo", lang: appLanguage),
                            isOn: $pomodoro.autoStartPomodoros,
                            tint: tint,
                            showDivider: true
                        )

                        automationToggle(
                            icon: "bell.badge.fill",
                            title: Localization.get("Enable Notifications", lang: appLanguage),
                            isOn: $pomodoro.notificationsEnabled,
                            tint: tint,
                            showDivider: true
                        )

                        automationToggle(
                            icon: "timer",
                            title: Localization.get("Show Focus Timer in Menu Bar", lang: appLanguage),
                            isOn: $pomodoro.showMenuBarClockDuringFocus,
                            tint: tint,
                            showDivider: false
                        )
                    }
                }

                AppSettingsCard(
                    title: Localization.get("Websites", lang: appLanguage)
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        WebsiteAccessModeRow(store: websiteBlocklistStore, tint: tint)

                        AppSettingsRow(showDivider: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(Localization.get(
                                    websiteBlocklistStore.accessMode == .allowAllExceptBlocked
                                        ? "Blocked Websites"
                                        : "Allowed Websites",
                                    lang: appLanguage
                                ))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))

                                switch websiteBlocklistStore.accessMode {
                                case .allowAllExceptBlocked:
                                    BlockedWebsitesList(store: websiteBlocklistStore, tint: tint)
                                        .padding(.top, 4)
                                case .blockAllExceptAllowed:
                                    AllowedWebsitesList(store: websiteBlocklistStore, tint: tint)
                                        .padding(.top, 4)
                                }
                            }
                            .id(websiteBlocklistStore.accessMode)
                            .transition(.opacity)
                        }

                        AppSettingsRow(showDivider: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        isAutoOpenUrlsExpanded.toggle()
                                    }
                                } label: {
                                    HStack {
                                        Text(Localization.get("Auto-open on Focus Start", lang: appLanguage))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Spacer()
                                        Image(systemName: isAutoOpenUrlsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isAutoOpenUrlsExpanded {
                                    AutoOpenUrlsList(store: websiteBlocklistStore, tint: tint)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: websiteBlocklistStore.accessMode)
    }

    private func durationControl(
        label: String,
        value: Int,
        range: ClosedRange<Int>,
        suffix: String = "m",
        tint: Color,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12).cornerRadius(6))

            TextField("", value: Binding(
                get: { value },
                set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }
            ), format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 28)
            .multilineTextAlignment(.center)

            Text(suffix)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04).cornerRadius(10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func automationToggle(
        icon: String,
        title: String,
        isOn: Binding<Bool>,
        tint: Color,
        showDivider: Bool = false
    ) -> some View {
        AppSettingsRow(showDivider: showDivider) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1).cornerRadius(8))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(NotchSwitchStyle(tint: tint))
                .labelsHidden()
        }
    }
}

private struct WebsiteAccessModeRow: View {
    @ObservedObject var store: FocusWebsiteBlocklistStore
    let tint: Color
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        AppSettingsRow(showDivider: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.get("Website Access Mode", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Text(Localization.get(modeDescription, lang: appLanguage))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()
                }

                NotchSegmentedPicker(
                    options: FocusWebsiteAccessMode.allCases,
                    selection: $store.accessMode,
                    titleMapper: { Localization.get($0.displayName, lang: appLanguage) },
                    tint: tint
                )
                .frame(maxWidth: 360)
            }
        }
    }

    private var modeDescription: String {
        switch store.accessMode {
        case .allowAllExceptBlocked:
            return "All websites work except domains in Blocked Websites."
        case .blockAllExceptAllowed:
            return "Only domains in Allowed Websites work during focus."
        }
    }
}

private struct BlockedWebsitesList: View {
    @ObservedObject var store: FocusWebsiteBlocklistStore
    let tint: Color
    @State private var newHost = ""
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField(Localization.get("Add website...", lang: appLanguage), text: $newHost)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit {
                        submit()
                    }

                Button(action: submit) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(tint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(FocusWebsiteBlocklistStore.normalizedHost(from: newHost) == nil)
                .opacity(FocusWebsiteBlocklistStore.normalizedHost(from: newHost) == nil ? 0.5 : 1.0)
            }

            if !store.blockedHosts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.blockedHosts, id: \.self) { host in
                        HStack {
                            Text(host)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))

                            Spacer()

                            Button {
                                store.removeHost(host)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
                .frame(maxHeight: 300)
                .padding(.top, 4)
            } else {
                Text(Localization.get("No websites blocked yet.", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 10)
            }

        }
    }

    private func submit() {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addHost(trimmed)
        newHost = ""
    }
}

private struct AllowedWebsitesList: View {
    @ObservedObject var store: FocusWebsiteBlocklistStore
    let tint: Color
    @State private var newHost = ""
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField(Localization.get("e.g. music.youtube.com", lang: appLanguage), text: $newHost)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit {
                        submit()
                    }

                Button(action: submit) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(tint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(FocusWebsiteBlocklistStore.normalizedHost(from: newHost) == nil)
                .opacity(FocusWebsiteBlocklistStore.normalizedHost(from: newHost) == nil ? 0.5 : 1.0)
            }

            if !store.allowedHosts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.allowedHosts, id: \.self) { host in
                        HStack {
                            Text(host)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))

                            Spacer()

                            Button {
                                store.removeAllowedHost(host)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
                .frame(maxHeight: 300)
                .padding(.top, 4)
            } else {
                Text(Localization.get("No allowed websites yet.", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 10)
            }

        }
    }

    private func submit() {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAllowedHost(trimmed)
        newHost = ""
    }
}

private struct AutoOpenUrlsList: View {
    @ObservedObject var store: FocusWebsiteBlocklistStore
    let tint: Color
    @State private var newUrl = ""
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField(Localization.get("e.g. notion.so or https://docs.google.com", lang: appLanguage), text: $newUrl)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .onSubmit {
                        submit()
                    }

                Button(action: submit) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(tint)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(newUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(newUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }

            if !store.autoOpenUrls.isEmpty {
                VStack(spacing: 6) {
                    ForEach(store.autoOpenUrls, id: \.self) { url in
                        HStack {
                            Text(url)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                var urls = store.autoOpenUrls
                                urls.removeAll { $0 == url }
                                store.setAutoOpenUrlsText(urls.joined(separator: "\n"))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.3))
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
                .frame(maxHeight: 300)
                .padding(.top, 4)
            } else {
                Text(Localization.get("No auto-open URLs yet.", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 10)
            }

            Text(String(format: Localization.get("%d URLs will open on focus start", lang: appLanguage), store.autoOpenUrls.count))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
        }
    }

    private func submit() {
        let trimmed = newUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var urls = store.autoOpenUrls
        guard !urls.contains(trimmed) else { return }
        urls.append(trimmed)
        store.setAutoOpenUrlsText(urls.joined(separator: "\n"))
        newUrl = ""
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

private struct AppFocusStatsSettingsView: View {
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
            return Localization.get("Last 7 Days", lang: appLanguage)
        }

        let localizedDay = Localization.get(selectedDay, lang: appLanguage)
        if appLanguage == "Tiếng Việt" {
            return localizedDay
        }
        return "\(Localization.get("Focus on", lang: appLanguage)) \(localizedDay)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                statValue(
                    label: displayedLabel,
                    value: learningStats.formattedDuration(displayedSeconds)
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    statValue(
                        label: Localization.get("Today", lang: appLanguage),
                        value: learningStats.formattedDuration(learningStats.todayLearningSeconds)
                    )
                    statValue(
                        label: Localization.get("Sessions", lang: appLanguage),
                        value: "\(learningStats.totalSessions)"
                    )
                    statValue(
                        label: Localization.get("Average", lang: appLanguage),
                        value: learningStats.formattedDuration(learningStats.averageSessionSeconds)
                    )
                    statValue(
                        label: Localization.get("Streak", lang: appLanguage),
                        value: "\(learningStats.streakDays)d"
                    )
                }
            }
            .frame(width: 260, alignment: .topLeading)

            Chart(chartData) { day in
                BarMark(
                    x: .value("Day", day.dayLabel),
                    y: .value("Minutes", Double(day.seconds) / 60.0)
                )
                .foregroundStyle(tint.gradient)
                .opacity(selectedDay == nil || selectedDay == day.dayLabel ? 1.0 : 0.42)
                .cornerRadius(5)
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: chartData.map { $0.dayLabel }) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(Localization.get(label, lang: appLanguage))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private func statValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.32))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct AppFocusCloudRankingSettingsView: View {
    @ObservedObject var focusCloudSync: FocusCloudSyncCoordinator
    let isBackendAuthenticated: Bool
    let tint: Color

    @State private var draftDisplayName = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSettingsRow(showDivider: true) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show me on leaderboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(isBackendAuthenticated ? focusCloudSync.statusText : "Sign in from Account settings to sync focus ranking.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { focusCloudSync.leaderboardOptIn },
                        set: { enabled in
                            Task { @MainActor in
                                isSaving = true
                                await focusCloudSync.updateLeaderboardProfile(
                                    optIn: enabled,
                                    displayName: draftDisplayName
                                )
                                draftDisplayName = focusCloudSync.displayName
                                isSaving = false
                            }
                        }
                    ))
                    .toggleStyle(NotchSwitchStyle(tint: tint))
                    .labelsHidden()
                    .disabled(!isBackendAuthenticated || isSaving)
                }
            }

            AppSettingsRow(showDivider: false) {
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    TextField("Display name", text: $draftDisplayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.28))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .disabled(!isBackendAuthenticated || isSaving)

                    Button {
                        Task { @MainActor in
                            isSaving = true
                            await focusCloudSync.updateLeaderboardProfile(
                                optIn: focusCloudSync.leaderboardOptIn,
                                displayName: draftDisplayName
                            )
                            draftDisplayName = focusCloudSync.displayName
                            isSaving = false
                        }
                    } label: {
                        Image(systemName: isSaving ? "clock.arrow.circlepath" : "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )
                    .disabled(!isBackendAuthenticated || isSaving)
                }
            }
        }
        .onAppear {
            draftDisplayName = focusCloudSync.displayName
        }
        .onChange(of: focusCloudSync.displayName) { _, value in
            draftDisplayName = value
        }
    }
}
