import AppKit
import NotchFocusCore
import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
    @ObservedObject var learningStats: LearningStatsStore
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject private var settingsController = AppSettingsController.shared
    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var hoveredTab: AppSettingsTab?

    private var versionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let shortVersion, let build, build != shortVersion {
            return "\(shortVersion) (\(build))"
        }
        return shortVersion ?? build ?? "1.0.0"
    }

    private var selectedTabTitle: String {
        Localization.get(settingsController.selectedTab.title, lang: appLanguage)
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
                    case .shortcuts:
                        AppShortcutsSettingsPane(shortcutStore: shortcutStore)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
        }
        .frame(minWidth: 980, minHeight: 720)
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notch")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))

            VStack(spacing: 8) {
                ForEach(AppSettingsTab.allCases) { tab in
                    let isSelected = settingsController.selectedTab == tab
                    let isHovered = hoveredTab == tab

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
                            isSelected
                                ? .black.opacity(0.84)
                                : (isHovered ? .white.opacity(0.92) : .white.opacity(0.72))
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    isSelected
                                        ? presentationModel.accentColor.ensureMinimumBrightness(factor: 0.78)
                                        : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredTab = hovering ? tab : nil
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 38) // Padding for window title bar area
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
        }
    }
}
