import SwiftUI

struct AppGeneralSettingsPane: View {
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

            AppSettingsCard(
                title: Localization.get("Display", lang: appLanguage)
            ) {
                AppSettingsRow(showDivider: true) {
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

                AppSettingsRow(showDivider: true) {
                    Image(systemName: "display.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    Text(Localization.get("Screen Display", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    NotchSegmentedPicker(
                        options: NotchScreenDisplayMode.allCases,
                        selection: Binding(
                            get: { presentationModel.selectedScreenDisplayMode },
                            set: { presentationModel.setScreenDisplayMode($0) }
                        ),
                        titleMapper: { Localization.get($0.displayNameKey, lang: appLanguage) },
                        tint: tint
                    )
                    .frame(width: 220)
                }

                AppSettingsRow(showDivider: false) {
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
                }
            }

            AppSettingsCard(
                title: Localization.get("Interaction", lang: appLanguage)
            ) {
                AppSettingsRow(showDivider: true) {
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
                }

                AppSettingsRow(showDivider: true) {
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
                }

                AppSettingsRow(showDivider: false) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    Text(Localization.get("Invisible", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    NotchSegmentedPicker(
                        options: NotchInvisibilityMode.allCases,
                        selection: Binding(
                            get: { presentationModel.selectedInvisibilityMode },
                            set: { presentationModel.setInvisibilityMode($0) }
                        ),
                        titleMapper: { Localization.get($0.displayNameKey, lang: appLanguage) },
                        tint: tint
                    )
                    .frame(width: 260)
                }
            }

            AppSettingsCard(
                title: Localization.get("System", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    settingToggle(
                        icon: "power.circle.fill",
                        title: Localization.get("Launch at Login", lang: appLanguage),
                        isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { updateLaunchAtLogin(to: $0) }
                        ),
                        tint: tint,
                        showDivider: true
                    )

                    if let launchAtLoginError, !launchAtLoginError.isEmpty {
                        Text(launchAtLoginError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 54)
                            .padding(.bottom, 12)
                    }

                    AppSettingsRow(showDivider: false) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(tint.opacity(0.1).cornerRadius(8))

                        Text(Localization.get("Version", lang: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        Spacer()

                        Text(versionLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
        }
        .onAppear(perform: refreshLaunchAtLoginState)
    }

    private func settingToggle(
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
