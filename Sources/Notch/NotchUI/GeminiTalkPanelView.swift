import AppKit
import SwiftUI

private enum GeminiSetupViewMode: Equatable {
    case home
    case agentSelection
}
private struct GeminiTalkToolToastChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.76))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
private struct GeminiTalkConnectedView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    let appLanguage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if !gemini.userTranscript.isEmpty {
                        Text(gemini.userTranscript)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Group {
                        if gemini.modelTranscript.isEmpty {
                            Text(Localization.get(gemini.connectedPlaceholderText, lang: appLanguage))
                                .foregroundStyle(.white.opacity(0.42))
                        } else {
                            ProgressiveRevealText(text: gemini.modelTranscript, animateOnAppear: false)
                                .foregroundStyle(.white.opacity(0.92))
                                .textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if gemini.isAutoReconnecting {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text(gemini.statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemYellow).ensureMinimumBrightness(factor: 0.72))
                }
            }

            if let toolAction = gemini.lastToolAction {
                HStack(spacing: 7) {
                    Image(systemName: toolAction.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(toolAction.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 6) {
                    GeminiInputModeMenu(gemini: gemini, presentationModel: presentationModel)
                    GeminiScreenShareMenu(gemini: gemini, presentationModel: presentationModel)
                    GeminiTranscriptModeToggle(gemini: gemini, presentationModel: presentationModel)
                    GeminiControlToggle(
                        icon: gemini.showLiveChatInput ? "keyboard.fill" : "keyboard",
                        label: Localization.get("Type", lang: appLanguage),
                        isActive: gemini.showLiveChatInput,
                        action: { gemini.showLiveChatInput.toggle() }
                    )
                    GeminiOutputVolumeControl(
                        value: Binding(
                            get: { gemini.outputVolume },
                            set: { gemini.setOutputVolume($0) }
                        )
                    )
                    GeminiControlToggle(
                        icon: "phone.down.fill",
                        label: Localization.get("End", lang: appLanguage),
                        isActive: true,
                        isDestructive: true,
                        action: { gemini.disconnect() }
                    )
                }
            }
        }
    }
}
private struct GeminiTalkProLockedView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    let appLanguage: String
    let themeAccent: Color

    private var decision: NotchPermissionDecision {
        entitlementStore.decision(for: .talkConnection)
    }

    private var actionTitle: String {
        switch decision.recoveryAction {
        case .signIn:
            return Localization.get("Sign in", lang: appLanguage)
        case .refresh:
            return Localization.get("Refresh Pro status", lang: appLanguage)
        case .upgrade:
            return Localization.get("Buy Notch Pro", lang: appLanguage)
        case .none:
            return Localization.get("Buy Notch Pro", lang: appLanguage)
        }
    }

    var body: some View {
        GeminiTalkPanelCard(tint: themeAccent) {
            HStack(spacing: 14) {
                GeminiTalkStateBadge(
                    title: Localization.get("Talk", lang: appLanguage),
                    tint: themeAccent
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(Localization.get(decision.message, lang: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 0)
                GeminiActionButton(
                    title: actionTitle,
                    icon: decision.recoveryAction == .refresh ? "arrow.clockwise" : "sparkles",
                    tint: themeAccent
                ) {
                    performRecoveryAction()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func performRecoveryAction() {
        switch decision.recoveryAction {
        case .signIn:
            gemini.openWebAccountLogin()
        case .refresh:
            Task { await gemini.refreshBackendSubscriptionStatus(forceRefresh: true) }
        case .upgrade:
            gemini.openWebProCheckout()
        case .none:
            break
        }
    }
}
private struct GeminiTalkDisconnectedHomeView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @Binding var setupViewMode: GeminiSetupViewMode
    let appLanguage: String
    let themeAccent: Color
    let statusColor: Color
    let selectedAgentAvatarSymbolName: String
    let selectedAgentAvatarImageURL: URL?
    let openSettingsPanel: () -> Void
    let beginCreatingAgent: () -> Void

    private var sortedSystemPromptPresets: [GeminiSystemPromptPreset] {
        gemini.systemPromptPresets.sorted { a, b in
            let dateA = a.lastUsedAt ?? Date.distantPast
            let dateB = b.lastUsedAt ?? Date.distantPast
            if dateA != dateB {
                return dateA > dateB
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if gemini.hasSavedAPIKey {
                switch setupViewMode {
                case .home:
                    setupHomeContent
                case .agentSelection:
                    agentSelectionView
                }
            } else {
                noGeminiKeySetupView
            }

            if let lastErrorMessage = gemini.lastErrorMessage {
                Text(Localization.get(lastErrorMessage, lang: appLanguage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var setupHomeContent: some View {
        GeminiTalkDraftHomeView(
            gemini: gemini,
            appLanguage: appLanguage,
            themeAccent: themeAccent,
            statusColor: statusColor,
            selectedAgentAvatarSymbolName: selectedAgentAvatarSymbolName,
            selectedAgentAvatarImageURL: selectedAgentAvatarImageURL,
            selectAgent: { setupViewMode = .agentSelection },
            openSettingsPanel: openSettingsPanel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }



    private var noGeminiKeySetupView: some View {
        GeminiTalkPanelCard(tint: themeAccent) {
            HStack(spacing: 14) {
                GeminiTalkStateBadge(
                    title: "Gemini",
                    tint: themeAccent
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(gemini.selectedConnectionSetupTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(gemini.selectedConnectionSetupDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                GeminiActionButton(
                    title: gemini.selectedConnectionManageButtonTitle,
                    icon: "key.fill",
                    tint: themeAccent
                ) {
                    openSettingsPanel()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var agentSelectionView: some View {
        GeminiAgentSelectionView(
            prompts: sortedSystemPromptPresets,
            selectedID: gemini.selectedSystemPromptID,
            statusColor: statusColor,
            onSelect: { id in
                gemini.selectSystemPrompt(id: id)
                setupViewMode = .home
            },
            onCreate: {
                beginCreatingAgent()
            },
            onDone: {
                setupViewMode = .home
            }
        )
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }
}
struct GeminiTalkPanelView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var headerAccessoryController: NotchHeaderAccessoryController
    @ObservedObject var presentationModel: NotchPresentationModel
    var appSettingsController: AppSettingsControlling = AppSettingsController.shared

    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @State private var setupViewMode: GeminiSetupViewMode = .home
    @State private var headerRefreshTask: Task<Void, Never>?

    private func scheduleHeaderRefresh() {
        headerRefreshTask?.cancel()
        headerRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            refreshHeaderAccessory()
        }
    }

    private var statusColor: Color {
        if gemini.canStartConnection || gemini.lifecycleState.isBusy {
            return themeAccent
        }
        return Color(nsColor: gemini.effectiveConnectionState.accentColor).ensureMinimumBrightness(factor: 0.72)
    }

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var selectedAgentAvatarSymbolName: String {
        gemini.selectedSystemPromptAvatarSymbolName
    }

    private var selectedAgentAvatarImageURL: URL? {
        gemini.selectedSystemPromptAvatarImageURL
    }

    private func beginCreatingAgent() {
        _ = gemini.createSystemPrompt()
        setupViewMode = .home
        openSettingsPanel()
    }

    private func refreshHeaderAccessory() {
        headerAccessoryController.clear()
    }

    private func openSettingsPanel() {
        appSettingsController.open(tab: .talk)
    }

    @ViewBuilder
    private var panelContent: some View {
        if gemini.showsConnectedSessionUI {
            GeminiTalkConnectedView(
                gemini: gemini,
                presentationModel: presentationModel,
                appLanguage: appLanguage
            )
        } else if gemini.requiresProForCurrentConnection {
            GeminiTalkProLockedView(
                gemini: gemini,
                entitlementStore: entitlementStore,
                appLanguage: appLanguage,
                themeAccent: themeAccent
            )
        } else {
            GeminiTalkDisconnectedHomeView(
                gemini: gemini,
                setupViewMode: $setupViewMode,
                appLanguage: appLanguage,
                themeAccent: themeAccent,
                statusColor: statusColor,
                selectedAgentAvatarSymbolName: selectedAgentAvatarSymbolName,
                selectedAgentAvatarImageURL: selectedAgentAvatarImageURL,
                openSettingsPanel: openSettingsPanel,
                beginCreatingAgent: beginCreatingAgent
            )
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            panelContent
            .padding(.bottom, gemini.showsConnectedSessionUI ? 4 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .onAppear(perform: scheduleHeaderRefresh)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: setupViewMode) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.hasSavedAPIKey) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.lifecycleState) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.isSavingAPIKey) { _, _ in
            scheduleHeaderRefresh()
        }
        .onDisappear {
            headerRefreshTask?.cancel()
            headerAccessoryController.clear()
        }
    }
}
