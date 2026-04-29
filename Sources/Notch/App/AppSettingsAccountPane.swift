import SwiftUI

struct AppAccountSettingsPane: View {
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
            AppSettingsPageTitle(
                title: Localization.get("Account", lang: appLanguage)
            )

            AppSettingsCard(
                title: Localization.get("Notch Account", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    AppSettingsRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(Localization.get(gemini.backendSignedInSummary ?? "Not signed in", lang: appLanguage))
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
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
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
