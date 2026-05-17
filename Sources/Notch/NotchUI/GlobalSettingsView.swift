import AppKit
import SwiftUI

struct GlobalSettingsView: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    private let launchAtLoginController = LaunchAtLoginController()

    private var tint: Color {
        presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
    }

    private var isShowingInlineAuthError: Bool {
        !gemini.isBackendAuthenticated
            && gemini.selectedConnectionMethod == .managedServer
    }

    private var appShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                generalSettingsSection

                Text("\(Localization.get("Version", lang: appLanguage)) \(appShortVersion)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if gemini.isBackendAuthenticated {
                            HStack(spacing: 8) {
                                Text(Localization.get(gemini.backendSignedInSummary ?? "Notch Account", lang: appLanguage))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))

                                Text(entitlementStore.planBadgeTitle)
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(entitlementStore.isProUser ? .black.opacity(0.85) : .white.opacity(0.92))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                entitlementStore.isProUser
                                                    ? Color(nsColor: .systemYellow)
                                                    : Color.white.opacity(0.14)
                                            )
                                    )
                                    .overlay {
                                        if !entitlementStore.isProUser {
                                            Capsule(style: .continuous)
                                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                        }
                                    }
                            }

                            Button(Localization.get("Sign out", lang: appLanguage)) {
                                Task { await gemini.logoutBackendAccount() }
                            }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Button(Localization.get("Sign in", lang: appLanguage)) {
                                    gemini.openWebAccountLogin()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tint)

                                Text(Localization.get("Continue in your browser. Notch will finish OAuth sign-in automatically.", lang: appLanguage))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }

                    Spacer(minLength: 16)

                    if gemini.isBackendAuthenticated && !entitlementStore.isProUser {
                        HStack(spacing: 8) {
                            StandardActionButton(
                                title: Localization.get("Buy Notch Pro", lang: appLanguage),
                                icon: "sparkles",
                                tint: tint,
                                variant: .primary
                            ) {
                                gemini.openWebProCheckout()
                            }

                            Button {
                                Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(tint)
                                    .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(tint.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(Localization.get("Refresh Pro status", lang: appLanguage))
                        }
                    }
                }


                if !gemini.isBackendAuthenticated {
                    VStack(alignment: .leading, spacing: 10) {
                        if let error = gemini.lastErrorMessage ?? gemini.backendAuthFailureMessage, !error.isEmpty {
                            Text(Localization.get(error, lang: appLanguage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                settingsGroupedDivider()

                Text(Localization.get("Appearance", lang: appLanguage))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))

                VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Localization.get("Language", lang: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))

                            HStack(spacing: 8) {
                                languageButton(name: "English")
                                languageButton(name: "Tiếng Việt")
                            }
                            .frame(maxWidth: .infinity)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(Localization.get("Accent", lang: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(NotchAccentColorOption.allCases) { option in
                                    accentColorButton(for: option)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(Localization.get("Hover to Open", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Text(hoverDelayLabel)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(tint)
                            }

                            Slider(
                                value: Binding(
                                    get: { presentationModel.hoverOpenDelaySeconds },
                                    set: { presentationModel.setHoverOpenDelay(seconds: $0) }
                                ),
                                in: 0.05...5.0,
                                step: 0.05
                            )
                            .tint(tint)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(Localization.get("Closed Notch Height", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Text(closedNotchHeightLabel)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(tint)
                            }

                            Slider(
                                value: Binding(
                                    get: { presentationModel.closedNotchHeight },
                                    set: { presentationModel.setClosedNotchHeight($0) }
                                ),
                                in: 1...32,
                                step: 1
                            )
                            .tint(tint)
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(Localization.get("Invisible", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            NotchSegmentedPicker(
                                options: NotchInvisibilityMode.allCases,
                                selection: Binding(
                                    get: { presentationModel.selectedInvisibilityMode },
                                    set: { presentationModel.setInvisibilityMode($0) }
                                ),
                                titleMapper: { Localization.get($0.displayNameKey, lang: appLanguage) },
                                tint: tint
                            )
                        }

                        settingsGroupedDivider()

                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { launchAtLoginEnabled },
                                set: { updateLaunchAtLogin(to: $0) }
                            )) {
                                Text(Localization.get("Launch at Login", lang: appLanguage))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .toggleStyle(NotchSwitchStyle(tint: tint))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let launchAtLoginError, !launchAtLoginError.isEmpty {
                                Text(launchAtLoginError)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
            }
            .padding(.horizontal, 13)

            StandardActionButton(
                title: Localization.get("Quit Notch", lang: appLanguage),
                icon: "power",
                tint: Color(nsColor: .systemRed).opacity(0.85),
                variant: .primary,
                fillsAvailableWidth: true
            ) {
                NSApp.terminate(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsGroupedDivider() -> some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }

    private var hoverDelayLabel: String {
        String(format: "%.2fs", presentationModel.hoverOpenDelaySeconds)
    }

    private var closedNotchHeightLabel: String {
        String(format: "%.0fpt", presentationModel.closedNotchHeight)
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginController.refreshStatus()
        launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    private func updateLaunchAtLogin(to enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginError = nil
            refreshLaunchAtLoginState()
        } catch {
            launchAtLoginError = error.localizedDescription
            refreshLaunchAtLoginState()
        }
    }

    private func settingsInputCard<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func settingsInlineInputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
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
                .frame(width: 24, height: 24)
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
