import AppKit
import Charts
import NotchFocusCore
import SwiftUI

enum AppSettingsTab: String, CaseIterable, Identifiable {
    case account
    case general
    case focus
    case talk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .account:
            return "Account"
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
        case .account:
            return "person.crop.circle"
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
        let entitlementStore: NotchEntitlementStore
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
        gemini: GeminiLiveViewModel,
        entitlementStore: NotchEntitlementStore
    ) {
        dependencies = Dependencies(
            presentationModel: presentationModel,
            pomodoro: pomodoro,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            learningStats: learningStats,
            gemini: gemini,
            entitlementStore: entitlementStore
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
            gemini: dependencies.gemini,
            entitlementStore: dependencies.entitlementStore
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
    @ObservedObject var entitlementStore: NotchEntitlementStore
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
                    case .account:
                        AppAccountSettingsPane(
                            gemini: gemini,
                            entitlementStore: entitlementStore
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
        }
        .padding(20)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.96))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
        }
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
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AppSettingsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize()
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.top, 6)
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
                title: Localization.get("General", lang: appLanguage)
            )

            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Language
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))
                    
                    Text(Localization.get("Language", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        languageButton(name: "English")
                        languageButton(name: "Tiếng Việt")
                    }
                }

                // MARK: - Accent Color
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(tint.opacity(0.1).cornerRadius(8))
                        
                        Text(Localization.get("Accent Color", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 10),
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(NotchAccentColorOption.allCases) { option in
                            accentColorButton(for: option)
                        }
                    }
                    .padding(.leading, 40)
                }

                // MARK: - Behavior
                VStack(alignment: .leading, spacing: 20) {
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Localization.get("Auto-Collapse Delay", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(String(format: "%.1fs", presentationModel.autoCollapseDelaySeconds))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                        }

                        Slider(
                            value: Binding(
                                get: { presentationModel.autoCollapseDelaySeconds },
                                set: { presentationModel.setAutoCollapseDelay(seconds: $0) }
                            ),
                            in: 0.05...5.0,
                            step: 0.05
                        )
                        .tint(tint)
                    }

                    settingToggle(
                        icon: "rectangle.inset.filled",
                        title: Localization.get("Hide in Fullscreen", lang: appLanguage),
                        isOn: Binding(
                            get: { presentationModel.hideInFullscreen },
                            set: { presentationModel.setHideInFullscreen($0) }
                        ),
                        tint: tint
                    )

                    settingToggle(
                        icon: "power.circle.fill",
                        title: Localization.get("Launch at Login", lang: appLanguage),
                        isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { updateLaunchAtLogin(to: $0) }
                        ),
                        tint: tint
                    )

                    if let launchAtLoginError, !launchAtLoginError.isEmpty {
                        Text(launchAtLoginError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 40)
                    }
                }

                Spacer()

                Spacer()
            }
            .padding(.top, 8)
        }
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private func settingToggle(
        icon: String,
        title: String,
        isOn: Binding<Bool>,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
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
                title: Localization.get("Focus", lang: appLanguage)
            )

            VStack(alignment: .leading, spacing: 28) {
                // MARK: - Stats
                AppFocusStatsSettingsView(learningStats: learningStats, tint: tint)

                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - Durations
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

                    // MARK: - Sound
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

                // MARK: - Automation
                VStack(alignment: .leading, spacing: 14) {
                    automationToggle(
                        icon: "play.circle.fill",
                        title: Localization.get("Auto Start Breaks", lang: appLanguage),
                        isOn: $pomodoro.autoStartBreaks,
                        tint: tint
                    )

                    automationToggle(
                        icon: "bolt.circle.fill",
                        title: Localization.get("Auto Start Pomo", lang: appLanguage),
                        isOn: $pomodoro.autoStartPomodoros,
                        tint: tint
                    )
                    
                    automationToggle(
                        icon: "bell.badge.fill",
                        title: Localization.get("Enable Notifications", lang: appLanguage),
                        isOn: $pomodoro.notificationsEnabled,
                        tint: tint
                    )
                }
                .padding(4)

                // MARK: - Blocked Websites
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "shield.slash.fill")
                            .foregroundStyle(.red.opacity(0.8))
                        Text(Localization.get("Blocked Websites", lang: appLanguage))
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))

                    BlockedWebsitesList(store: websiteBlocklistStore, tint: tint)
                }

                // MARK: - Allowed Websites
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green.opacity(0.8))
                        Text(Localization.get("Allowed Websites", lang: appLanguage))
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))

                    AllowedWebsitesList(store: websiteBlocklistStore, tint: tint)
                }
                
                // MARK: - Auto-open
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.up.right.square.fill")
                            .foregroundStyle(.blue.opacity(0.8))
                        Text(Localization.get("Auto-open on Focus Start", lang: appLanguage))
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))

                    AutoOpenUrlsList(store: websiteBlocklistStore, tint: tint)
                }
            }
            .padding(.top, 8)
        }
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
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
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

private struct AllowedWebsitesList: View {
    @ObservedObject var store: FocusWebsiteBlocklistStore
    let tint: Color
    @State private var newHost = ""
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("e.g. music.youtube.com", text: $newHost)
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
                Text("No allowed websites yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 10)
            }

            Text("\(store.allowedHosts.count) domains will never be blocked")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
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
                TextField("e.g. notion.so or https://docs.google.com", text: $newUrl)
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
                Text("No auto-open URLs yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 10)
            }

            Text("\(store.autoOpenUrls.count) URLs will open on focus start")
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

private struct AppAccountSettingsPane: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var tint: Color {
        settingsAccentColor(from: accentColorID)
    }

    private var entitlementStatusMessage: String? {
        switch entitlementStore.snapshot.verification {
        case .gracePeriod where entitlementStore.snapshot.plan == .pro:
            return "Offline Pro grace period is active."
        case .expired:
            return "Pro status is expired. Refresh your account to verify access."
        case .unknown:
            return "Pro status has not been verified yet."
        case .verified, .gracePeriod:
            return nil
        }
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsCard(
                title: Localization.get("Notch Account", lang: appLanguage),
                subtitle: Localization.get("Manage your Notch account and Pro subscription.", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(gemini.backendSignedInSummary ?? Localization.get("Not signed in", lang: appLanguage))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))

                                Text(entitlementStore.planBadgeTitle)
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(entitlementStore.isProUser ? .black.opacity(0.84) : .white.opacity(0.9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                entitlementStore.isProUser
                                                    ? Color(nsColor: .systemYellow)
                                                    : Color.white.opacity(0.12)
                                            )
                                    )
                                    .overlay {
                                        if !entitlementStore.isProUser {
                                            Capsule(style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        }
                                    }
                            }

                            Text(Localization.get(accountHelperText, lang: appLanguage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                                .fixedSize(horizontal: false, vertical: true)

                            if let entitlementStatusMessage {
                                Text(Localization.get(entitlementStatusMessage, lang: appLanguage))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.48))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 16)

                        HStack(spacing: 8) {
                            if gemini.isBackendAuthenticated {
                                if !entitlementStore.isProUser {
                                    StandardActionButton(
                                        title: Localization.get("Buy Notch Pro", lang: appLanguage),
                                        icon: "sparkles",
                                        tint: tint,
                                        variant: .primary
                                    ) {
                                        gemini.openWebProCheckout()
                                    }
                                }

                                Button {
                                    Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(tint.opacity(0.85))
                                        .padding(5)
                                        .background(Color.white.opacity(0.06).cornerRadius(6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(Localization.get("Refresh Pro status", lang: appLanguage))

                                Button {
                                    Task { await gemini.logoutBackendAccount() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                        Text(Localization.get("Sign out", lang: appLanguage))
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06).cornerRadius(6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                StandardActionButton(
                                    title: Localization.get("Log in", lang: appLanguage),
                                    icon: "person.crop.circle.badge.checkmark",
                                    tint: tint,
                                    variant: .primary
                                ) {
                                    gemini.openWebAccountLogin()
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
        }
    }

    private var accountHelperText: String {
        if gemini.isBackendAuthenticated {
            return entitlementStore.isProUser
                ? "Your account has Notch Pro access."
                : "Upgrade to Notch Pro to unlock Talk."
        }
        return "Sign in to verify Pro access and sync your subscription."
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


            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(Localization.get("Connection Method", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    NotchSegmentedPicker(
                        options: GeminiLiveConnectionMethod.allCases,
                        selection: $gemini.selectedConnectionMethod,
                        titleMapper: { $0.title },
                        tint: tint
                    )
                    .frame(width: 220)
                }

                if gemini.selectedConnectionMethod == .userAPIKey {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("AIza...", text: $gemini.apiKeyText)
                            .textFieldStyle(.roundedBorder)

                        StandardActionButton(
                            title: gemini.isSavingAPIKey ? "Saving..." : Localization.get("Save API key to local", lang: appLanguage),
                            icon: "key.fill",
                            tint: tint,
                            variant: .primary,
                            isDisabled: gemini.isSavingAPIKey
                        ) {
                            Task { await gemini.saveAPIKey() }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Localization.get("Managed server uses your Notch Account.", lang: appLanguage))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(Localization.get("Sign in and manage Pro from the Account tab.", lang: appLanguage))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)

                        StandardActionButton(
                            title: Localization.get("Open Account Settings", lang: appLanguage),
                            icon: "person.crop.circle",
                            tint: tint,
                            variant: .primary
                        ) {
                            AppSettingsController.shared.open(tab: .account)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let error = gemini.lastErrorMessage ?? gemini.backendAuthFailureMessage, !error.isEmpty {
                    Text(Localization.get(error, lang: appLanguage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }


            HoldToTalkShortcutRecorderView(
                shortcut: $holdShortcut,
                title: Localization.get("Push to Talk key", lang: appLanguage),
                helperText: nil,
                isNotchStyle: true,
                tint: tint
            )

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.get("User Profile", lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    GeminiFileTextEditor(text: $userProfileDraft)
                        .onChange(of: userProfileDraft) { _, newValue in
                            if gemini.userProfileContent != newValue {
                                gemini.saveUserProfile(newValue)
                            }
                        }
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.get("Memory", lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    GeminiFileTextEditor(text: $memoryDraft)
                        .onChange(of: memoryDraft) { _, newValue in
                            if gemini.memoryContent != newValue {
                                gemini.saveMemory(newValue)
                            }
                        }
                }
            }

            agentEditorPanel

        }
        .onAppear(perform: syncDrafts)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in syncAgentDrafts() }
        .onChange(of: gemini.userProfileContent) { _, v in userProfileDraft = v }
        .onChange(of: gemini.memoryContent) { _, v in memoryDraft = v }
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

    @ViewBuilder
    private var agentEditorPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            agentListColumn
            agentDetailColumn
        }
        .frame(maxWidth: .infinity, minHeight: 480)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var agentListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Localization.get("Agents", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                Button {
                    _ = gemini.createSystemPrompt()
                    syncAgentDrafts()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.07))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(gemini.systemPromptPresets, id: \.id) { prompt in
                        AgentListRow(
                            prompt: prompt,
                            isSelected: gemini.selectedSystemPromptID == prompt.id,
                            tint: tint
                        ) {
                            gemini.selectSystemPrompt(id: prompt.id)
                            syncAgentDrafts()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
        }
        .frame(width: 200)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
        }
    }

    @ViewBuilder
    private var agentDetailColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Identity header
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06))
                        GeminiAgentAvatarArtwork(
                            imageURL: gemini.selectedSystemPromptAvatarImageURL,
                            symbolName: gemini.selectedSystemPromptAvatarSymbolName,
                            symbolFont: .system(size: 20, weight: .semibold),
                            size: 48
                        )
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(Localization.get("Agent name (optional)", lang: appLanguage), text: $agentNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .semibold))
                            .onChange(of: agentNameDraft) { _, newValue in
                                _ = gemini.saveSystemPrompt(id: currentPromptID, title: newValue, content: agentPromptDraft)
                            }

                        HStack(spacing: 6) {
                            StandardActionButton(
                                title: Localization.get("Change Photo", lang: appLanguage),
                                icon: "photo", tint: tint, variant: .primary,
                                isDisabled: !gemini.canManageSkills
                            ) { gemini.chooseSelectedSystemPromptAvatarImage() }

                            if gemini.selectedSystemPromptAvatarImageURL != nil {
                                StandardActionButton(
                                    title: Localization.get("Clear", lang: appLanguage),
                                    icon: "xmark", tint: tint
                                ) { gemini.clearSelectedSystemPromptAvatarImage() }
                            }
                            Spacer()
                            StandardActionButton(
                                title: Localization.get("Delete Agent", lang: appLanguage),
                                icon: "trash",
                                tint: Color(nsColor: .systemRed).opacity(0.85),
                                variant: .primary,
                                isDisabled: !gemini.canDeleteSelectedSystemPrompt
                            ) { showingDeleteAgentAlert = true }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.07))

                // Voice / Model / Thinking
                HStack(spacing: 12) {
                    Picker("Model", selection: $gemini.selectedModel) {
                        ForEach(GeminiLiveModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.menu)
                    Picker(Localization.get("Voice", lang: appLanguage), selection: $gemini.selectedVoice) {
                        ForEach(GeminiVoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu)
                    Picker(Localization.get("Thinking", lang: appLanguage), selection: $gemini.thinkingLevel) {
                        ForEach(GeminiThinkingLevel.allCases, id: \.self) {
                            Text(Localization.get($0.rawValue, lang: appLanguage)).tag($0)
                        }
                    }.pickerStyle(.menu)
                }

                Divider().overlay(Color.white.opacity(0.07))

                // System Prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.get("System Prompt", lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.42))
                    GeminiFileTextEditor(text: $agentPromptDraft)
                        .onChange(of: agentPromptDraft) { _, newValue in
                            _ = gemini.saveSystemPrompt(id: currentPromptID, title: agentNameDraft, content: newValue)
                        }
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 8) {
                    GeminiToolsPicker(selection: $gemini.enabledTools, isDisabled: !gemini.canManageSkills)
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 8) {
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
            .padding(18)
        }
        .frame(maxWidth: .infinity)
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

private struct AgentListRow: View {
    let prompt: GeminiSystemPromptPreset
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GeminiAgentAvatarArtwork(
                    imageURL: prompt.resolvedAvatarImageURL,
                    symbolName: prompt.resolvedAvatarSymbolName,
                    symbolFont: .system(size: 12, weight: .semibold),
                    size: 28
                )
                Text(prompt.title.isEmpty ? "Untitled" : prompt.title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Circle().fill(tint).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
