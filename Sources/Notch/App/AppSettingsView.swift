import AppKit
import Charts
import NotchFocusCore
import SwiftUI

enum AppSettingsTab: String, CaseIterable, Identifiable {
    case general
    case focus
    case talk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .focus:
            return "Focus"
        case .talk:
            return "Talk"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .focus:
            return "timer"
        case .talk:
            return "bubble.left.and.bubble.right"
        }
    }
}

@MainActor
final class AppSettingsController: ObservableObject {
    static let shared = AppSettingsController()

    private struct Dependencies {
        let presentationModel: NotchPresentationModel
        let pomodoro: PomodoroViewModel
        let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
        let learningStats: LearningStatsStore
        let gemini: GeminiLiveViewModel
    }

    @Published var selectedTab: AppSettingsTab = .general
    private var dependencies: Dependencies?
    private var window: NSWindow?
    private var hostingController: NSHostingController<AppSettingsView>?

    func configure(
        presentationModel: NotchPresentationModel,
        pomodoro: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        learningStats: LearningStatsStore,
        gemini: GeminiLiveViewModel
    ) {
        dependencies = Dependencies(
            presentationModel: presentationModel,
            pomodoro: pomodoro,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            learningStats: learningStats,
            gemini: gemini
        )

        updateRootViewIfNeeded()
    }

    func open(tab: AppSettingsTab = .general) {
        selectedTab = tab
        guard let dependencies else { return }

        let window = makeWindowIfNeeded(using: dependencies)
        updateRootViewIfNeeded()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.center()
    }

    private func makeWindowIfNeeded(using dependencies: Dependencies) -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: makeRootView(using: dependencies))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Notch Settings"
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 900, height: 640)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()

        self.hostingController = hostingController
        self.window = window
        return window
    }

    private func updateRootViewIfNeeded() {
        guard let dependencies, let hostingController else { return }
        hostingController.rootView = makeRootView(using: dependencies)
    }

    private func makeRootView(using dependencies: Dependencies) -> AppSettingsView {
        AppSettingsView(
            presentationModel: dependencies.presentationModel,
            pomodoro: dependencies.pomodoro,
            focusWebsiteBlocklistStore: dependencies.focusWebsiteBlocklistStore,
            learningStats: dependencies.learningStats,
            gemini: dependencies.gemini
        )
    }
}

private func settingsAccentColor(from rawValue: String) -> Color {
    NotchAccentColorOption.resolve(rawValue: rawValue).brightColor
}

private func settingsFormattedAgentDisplayName(_ raw: String) -> String {
    let collapsed = raw
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return collapsed.isEmpty ? "Untitled Agent" : collapsed
}

struct AppSettingsView: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject private var settingsController = AppSettingsController.shared
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var versionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let shortVersion, let build, build != shortVersion {
            return "\(shortVersion) (\(build))"
        }
        return shortVersion ?? build ?? "1.0.0"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch settingsController.selectedTab {
                    case .general:
                        AppGeneralSettingsPane(
                            presentationModel: presentationModel,
                            versionLabel: versionLabel
                        )
                    case .focus:
                        AppFocusSettingsPane(
                            pomodoro: pomodoro,
                            websiteBlocklistStore: focusWebsiteBlocklistStore,
                            learningStats: learningStats
                        )
                    case .talk:
                        AppTalkSettingsPane(gemini: gemini)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
        }
        .frame(minWidth: 980, minHeight: 720)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notch")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(Localization.get("General Settings", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            VStack(spacing: 8) {
                ForEach(AppSettingsTab.allCases) { tab in
                    Button {
                        settingsController.selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 16)
                            Text(Localization.get(tab.title, lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(
                            settingsController.selectedTab == tab
                                ? .black.opacity(0.84)
                                : .white.opacity(0.72)
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    settingsController.selectedTab == tab
                                        ? presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
                                        : Color.white.opacity(0.06)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Text("Version \(versionLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(20)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96))
    }
}

private struct AppSettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct AppSettingsPageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppSettingsPaneStack<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: 920, alignment: .leading)
    }
}

private struct AppGeneralSettingsPane: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    let versionLabel: String
    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    private let launchAtLoginController = LaunchAtLoginController()

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("General", lang: appLanguage),
                subtitle: "Shared app appearance and behavior live here now, not inside the notch."
            )

            AppSettingsCard(
                title: Localization.get("Appearance", lang: appLanguage),
                subtitle: "These settings apply across Focus, Talk, and the rest of the app."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Localization.get("Language", lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))

                        HStack(spacing: 8) {
                            languageButton(name: "English")
                            languageButton(name: "Tiếng Việt")
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.06))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Localization.get("Accent Color", lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(NotchAccentColorOption.allCases) { option in
                                accentColorButton(for: option)
                            }
                        }
                    }
                }
            }

            AppSettingsCard(
                title: "Behavior",
                subtitle: "Controls how the notch appears and when it opens."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Localization.get("Hover Open Delay", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(String(format: "%.2fs", presentationModel.hoverOpenDelaySeconds))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                        }

                        Slider(
                            value: Binding(
                                get: { presentationModel.hoverOpenDelaySeconds },
                                set: { presentationModel.setHoverOpenDelay(seconds: $0) }
                            ),
                            in: 0.05...1.0,
                            step: 0.05
                        )
                        .tint(tint)
                    }

                    Toggle(isOn: Binding(
                        get: { presentationModel.hideInFullscreen },
                        set: { presentationModel.setHideInFullscreen($0) }
                    )) {
                        Text(Localization.get("Hide in Fullscreen", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { updateLaunchAtLogin(to: $0) }
                        )) {
                            Text(Localization.get("Launch at Login", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .toggleStyle(NotchSwitchStyle(tint: tint))

                        if let launchAtLoginError, !launchAtLoginError.isEmpty {
                            Text(launchAtLoginError)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text("Version \(versionLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginController.refreshStatus()
        launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    private func updateLaunchAtLogin(to enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLoginState()
    }

    private func languageButton(name: String) -> some View {
        StandardActionButton(
            title: name,
            tint: tint,
            variant: appLanguage == name ? .primary : .secondary,
            action: { appLanguage = name }
        )
    }

    private func accentColorButton(for option: NotchAccentColorOption) -> some View {
        let isSelected = presentationModel.selectedAccentColorOption == option
        let optionColor = option.color.ensureMinimumBrightness(factor: 0.78)

        return Button {
            presentationModel.setAccentColor(option)
        } label: {
            Circle()
                .fill(optionColor)
                .frame(width: 26, height: 26)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct AppFocusSettingsPane: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var websiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var learningStats: LearningStatsStore
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
                subtitle: "Pomodoro timings and focus automation now live in app settings."
            )

            AppSettingsCard(
                title: Localization.get("Stats", lang: appLanguage),
                subtitle: "Review Focus time without opening any panel inside the notch."
            ) {
                AppFocusStatsSettingsView(learningStats: learningStats, tint: tint)
            }

            AppSettingsCard(
                title: "Durations",
                subtitle: "Edit the focus cycle directly with explicit durations."
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    numberField(
                        label: Localization.get("Focus", lang: appLanguage),
                        value: pomodoro.focusMinutes,
                        range: 5...180
                    ) {
                        pomodoro.updateCurrentDurations(
                            focusMinutes: $0,
                            breakMinutes: pomodoro.breakMinutes
                        )
                    }

                    numberField(
                        label: Localization.get("Short", lang: appLanguage),
                        value: pomodoro.breakMinutes,
                        range: 1...60
                    ) {
                        pomodoro.updateCurrentDurations(
                            focusMinutes: pomodoro.focusMinutes,
                            breakMinutes: $0
                        )
                    }

                    numberField(
                        label: Localization.get("Long", lang: appLanguage),
                        value: pomodoro.longBreakDurationSeconds / 60,
                        range: 1...60
                    ) {
                        pomodoro.updateLongBreakDuration(minutes: $0)
                    }

                    numberField(
                        label: Localization.get("Cycle", lang: appLanguage),
                        value: pomodoro.sessionsBeforeLongBreak,
                        range: 1...12
                    ) {
                        pomodoro.updateSessionsBeforeLongBreak(count: $0)
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("Sound", lang: appLanguage),
                subtitle: "Choose the bundled sound that plays when focus and break phases switch."
            ) {
                Picker("Sound", selection: $focusTransitionSoundID) {
                    ForEach(FocusTransitionSoundOption.allCases) { option in
                        Text(Localization.get(option.displayName, lang: appLanguage))
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
                .onChange(of: focusTransitionSoundID) { _, _ in
                    SoundManager.previewFocusTransitionSound(selectedFocusTransitionSound)
                }
            }

            AppSettingsCard(
                title: "Automation",
                subtitle: "These defaults control how Focus progresses from one phase to the next."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $pomodoro.autoStartBreaks) {
                        Text(Localization.get("Auto Start Breaks", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))

                    Toggle(isOn: $pomodoro.autoStartPomodoros) {
                        Text(Localization.get("Auto Start Pomo", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))
                }
            }

            AppSettingsCard(
                title: "Blocked Websites",
                subtitle: "The Chrome bridge reads this list live while Focus is running."
            ) {
                BlockedWebsitesList(store: websiteBlocklistStore, tint: tint)
            }
        }
    }

    private func numberField(
        label: String,
        value: Int,
        range: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))

            TextField("", value: Binding(
                get: { value },
                set: { newValue in
                    onChange(min(max(newValue, range.lowerBound), range.upperBound))
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
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

            Text("\(store.blockedHosts.count) domains synced to Chrome extension")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
        }
    }

    private func submit() {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addHost(trimmed)
        newHost = ""
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

private struct AppTalkSettingsPane: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @State private var holdShortcut = HoldToTalkShortcutStore.load()
    @State private var agentNameDraft = ""
    @State private var agentPromptDraft = ""
    @State private var userProfileDraft = ""
    @State private var memoryDraft = ""
    @State private var showingDeleteAgentAlert = false

    private var tint: Color {
        settingsAccentColor(from: accentColorID)
    }

    private var inputModeBinding: Binding<GeminiLiveInputMode> {
        Binding(
            get: { gemini.inputMode },
            set: { gemini.setInputMode($0) }
        )
    }

    private var currentPromptID: String {
        gemini.selectedSystemPromptID
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Gemini Live", lang: appLanguage),
                subtitle: "Talk configuration, account setup, prompts, tools, and skills now live here."
            )

            AppSettingsCard(
                title: Localization.get("Connection Method", lang: appLanguage),
                subtitle: Localization.get("Choose how Notch connects to Gemini Live across the app.", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Connection Method", selection: $gemini.selectedConnectionMethod) {
                        ForEach(GeminiLiveConnectionMethod.allCases) { method in
                            Text(method.title)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if gemini.selectedConnectionMethod == .userAPIKey {
                        VStack(alignment: .leading, spacing: 10) {
                            SecureField("AIza...", text: $gemini.apiKeyText)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                StandardActionButton(
                                    title: gemini.isSavingAPIKey ? "Saving..." : Localization.get("Save API key", lang: appLanguage),
                                    icon: "key.fill",
                                    tint: tint,
                                    variant: .primary,
                                    isDisabled: gemini.isSavingAPIKey
                                ) {
                                    Task { await gemini.saveAPIKey() }
                                }

                                if gemini.hasSavedAPIKey {
                                    Text(Localization.get("Saved", lang: appLanguage))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(nsColor: .systemGreen))
                                }
                            }

                            Text(Localization.get("This key is stored locally on your Mac and used directly by Notch.", lang: appLanguage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text(gemini.backendSignedInSummary ?? Localization.get("Not subscribed", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))

                                Text(gemini.isProUser ? "PRO" : "FREE")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(gemini.isProUser ? .black.opacity(0.84) : .white.opacity(0.9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                gemini.isProUser
                                                    ? Color(nsColor: .systemYellow)
                                                    : Color.white.opacity(0.12)
                                            )
                                    )
                            }

                            HStack(spacing: 8) {
                                if gemini.isBackendAuthenticated {
                                    StandardActionButton(
                                        title: Localization.get("Sign out", lang: appLanguage),
                                        icon: "rectangle.portrait.and.arrow.right",
                                        tint: Color(nsColor: .systemRed).opacity(0.85),
                                        variant: .primary
                                    ) {
                                        Task { await gemini.logoutBackendAccount() }
                                    }
                                } else {
                                    StandardActionButton(
                                        title: Localization.get("Log in", lang: appLanguage),
                                        icon: "person.crop.circle.badge.checkmark",
                                        tint: tint,
                                        variant: .primary
                                    ) {
                                        gemini.openWebAccountLogin()
                                    }

                                    StandardActionButton(
                                        title: Localization.get("Sign up", lang: appLanguage),
                                        icon: "person.badge.plus",
                                        tint: tint
                                    ) {
                                        gemini.openWebAccountSignup()
                                    }
                                }

                                if !gemini.isProUser {
                                    StandardActionButton(
                                        title: Localization.get("Buy Notch Pro", lang: appLanguage),
                                        icon: "sparkles",
                                        tint: tint
                                    ) {
                                        gemini.openWebProCheckout()
                                    }
                                }

                                StandardActionButton(
                                    title: Localization.get("Refresh Pro status", lang: appLanguage),
                                    icon: "arrow.clockwise",
                                    tint: tint
                                ) {
                                    Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
                                }
                            }
                        }
                    }

                    if let error = gemini.lastErrorMessage ?? gemini.backendAuthFailureMessage, !error.isEmpty {
                        Text(Localization.get(error, lang: appLanguage))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            AppSettingsCard(
                title: "Talk Defaults",
                subtitle: "Persistent Talk behavior shared across sessions."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(Localization.get("Open Mic", lang: appLanguage), selection: inputModeBinding) {
                        Text(Localization.get("Open Mic", lang: appLanguage))
                            .tag(GeminiLiveInputMode.openMic)
                        Text(Localization.get("Push to Talk", lang: appLanguage))
                            .tag(GeminiLiveInputMode.pushToTalk)
                    }
                    .pickerStyle(.segmented)

                    HoldToTalkShortcutRecorderView(
                        shortcut: $holdShortcut,
                        title: Localization.get("Push to Talk", lang: appLanguage),
                        helperText: Localization.get("Push to Talk hint", lang: appLanguage),
                        tint: tint
                    )

                    Toggle(isOn: Binding(
                        get: { gemini.showTranscriptOverlay },
                        set: { gemini.setTranscriptOverlayEnabled($0) }
                    )) {
                        Text("Transcript Overlay")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))

                    Toggle(isOn: $gemini.transcriptOverlayAutoHide) {
                        Text(Localization.get("Auto Hide", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))

                    Toggle(isOn: $gemini.showLiveChatInput) {
                        Text("Show Chat Input")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .toggleStyle(NotchSwitchStyle(tint: tint))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model Volume")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text("\(Int((gemini.outputVolume * 100).rounded()))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                        }

                        Slider(
                            value: Binding(
                                get: { gemini.outputVolume },
                                set: { gemini.setOutputVolume($0) }
                            ),
                            in: 0...1
                        )
                        .tint(tint)
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("Agent", lang: appLanguage),
                subtitle: "Model, prompt, and identity settings for the currently selected Talk agent."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.06))

                            GeminiAgentAvatarArtwork(
                                imageURL: gemini.selectedSystemPromptAvatarImageURL,
                                symbolName: gemini.selectedSystemPromptAvatarSymbolName,
                                symbolFont: .system(size: 20, weight: .semibold),
                                size: 48
                            )
                        }
                        .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Agent", selection: Binding(
                                get: { gemini.selectedSystemPromptID },
                                set: { gemini.selectSystemPrompt(id: $0) }
                            )) {
                                ForEach(gemini.systemPromptPresets) { prompt in
                                    Text(settingsFormattedAgentDisplayName(prompt.title))
                                        .tag(prompt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 260, alignment: .leading)

                            HStack(spacing: 8) {
                                StandardActionButton(
                                    title: Localization.get("New Agent", lang: appLanguage),
                                    icon: "plus",
                                    tint: tint,
                                    variant: .primary
                                ) {
                                    _ = gemini.createSystemPrompt()
                                    syncAgentDrafts()
                                }

                                StandardActionButton(
                                    title: Localization.get("Delete Agent", lang: appLanguage),
                                    icon: "trash",
                                    tint: Color(nsColor: .systemRed).opacity(0.85),
                                    variant: .primary,
                                    isDisabled: !gemini.canDeleteSelectedSystemPrompt
                                ) {
                                    showingDeleteAgentAlert = true
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 8) {
                            StandardActionButton(
                                title: Localization.get("Change Photo", lang: appLanguage),
                                icon: "photo",
                                tint: tint,
                                variant: .primary,
                                isDisabled: !gemini.canManageSkills
                            ) {
                                gemini.chooseSelectedSystemPromptAvatarImage()
                            }

                            StandardActionButton(
                                title: Localization.get("Clear", lang: appLanguage),
                                icon: "xmark",
                                tint: tint,
                                isDisabled: gemini.selectedSystemPromptAvatarImageURL == nil
                            ) {
                                gemini.clearSelectedSystemPromptAvatarImage()
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Picker("Model", selection: $gemini.selectedModel) {
                            ForEach(GeminiLiveModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(Localization.get("Voice", lang: appLanguage), selection: $gemini.selectedVoice) {
                            ForEach(GeminiVoice.allCases, id: \.self) { voice in
                                Text(voice.rawValue).tag(voice)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(Localization.get("Thinking", lang: appLanguage), selection: $gemini.thinkingLevel) {
                            ForEach(GeminiThinkingLevel.allCases, id: \.self) { level in
                                Text(Localization.get(level.rawValue, lang: appLanguage)).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Localization.get("Name", lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))

                        TextField(Localization.get("Agent name (optional)", lang: appLanguage), text: $agentNameDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Localization.get("System Prompt", lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))

                        GeminiFileTextEditor(text: $agentPromptDraft)
                    }

                    StandardActionButton(
                        title: Localization.get("Save", lang: appLanguage),
                        icon: "square.and.arrow.down",
                        tint: tint,
                        variant: .primary
                    ) {
                        _ = gemini.saveSystemPrompt(
                            id: currentPromptID,
                            title: agentNameDraft,
                            content: agentPromptDraft
                        )
                        syncAgentDrafts()
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("User Profile", lang: appLanguage),
                subtitle: "Injected into the Talk context as persistent user-specific context."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    GeminiFileTextEditor(text: $userProfileDraft)

                    StandardActionButton(
                        title: Localization.get("Save User Profile", lang: appLanguage),
                        icon: "person.text.rectangle",
                        tint: tint,
                        variant: .primary
                    ) {
                        gemini.saveUserProfile(userProfileDraft)
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("Memory", lang: appLanguage),
                subtitle: "Durable cross-session memory used by Talk."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    GeminiFileTextEditor(text: $memoryDraft)

                    StandardActionButton(
                        title: Localization.get("Save Memory", lang: appLanguage),
                        icon: "bookmark.fill",
                        tint: tint,
                        variant: .primary
                    ) {
                        gemini.saveMemory(memoryDraft)
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("Tools", lang: appLanguage),
                subtitle: "Tool permissions are now managed from Settings instead of the notch."
            ) {
                GeminiToolsPicker(
                    selection: $gemini.enabledTools,
                    isDisabled: !gemini.canManageSkills
                )
            }

            AppSettingsCard(
                title: Localization.get("Skills", lang: appLanguage),
                subtitle: "Install, enable, or remove Talk skills here."
            ) {
                GeminiSkillsPicker(
                    installedSkills: gemini.installedSkills,
                    userSkillNames: Set(gemini.userInstalledSkills.map(\.metadata.name)),
                    selection: $gemini.enabledSkillNames,
                    isDisabled: !gemini.canManageSkills,
                    onImport: { gemini.importSkill() },
                    onDeleteName: { gemini.deleteSkill(named: $0) }
                )
            }
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in
            syncAgentDrafts()
        }
        .onChange(of: gemini.userProfileContent) { _, newValue in
            userProfileDraft = newValue
        }
        .onChange(of: gemini.memoryContent) { _, newValue in
            memoryDraft = newValue
        }
        .alert(Localization.get("Delete Agent?", lang: appLanguage), isPresented: $showingDeleteAgentAlert) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {}
            Button(Localization.get("Delete", lang: appLanguage), role: .destructive) {
                _ = gemini.deleteSelectedSystemPrompt()
                syncAgentDrafts()
            }
        } message: {
            Text("Delete \"\(settingsFormattedAgentDisplayName(gemini.selectedSystemPromptPreset.title))\"?")
        }
    }

    private func syncDrafts() {
        syncAgentDrafts()
        userProfileDraft = gemini.userProfileContent
        memoryDraft = gemini.memoryContent
        holdShortcut = HoldToTalkShortcutStore.load()
    }

    private func syncAgentDrafts() {
        let selected = gemini.selectedSystemPromptPreset
        agentNameDraft = selected.title
        agentPromptDraft = selected.content
    }
}
