import AppKit
import SwiftUI

private enum GeminiPanelControlPalette {
    static let liveInactiveFill = Color.white.opacity(0.08)
    static let liveInactiveStroke = Color.white.opacity(0.08)
}

private func themedNotchAccentColor(from accentColorID: String) -> Color {
    NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
}

private func formattedAgentDisplayName(_ raw: String) -> String {
    let collapsed = raw
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return collapsed.isEmpty ? "Untitled Agent" : collapsed
}

private enum GeminiSetupViewMode: Equatable {
    case home
    case agentSelection
}

private struct GeminiDualPill: View {
    let leftIcon: String
    let leftTitle: String
    let leftSubtitle: String
    let rightIcon: String
    let rightTitle: String
    let rightSubtitle: String
    let tint: Color
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: leftIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(leftTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(leftSubtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            
            Spacer(minLength: 12)
            
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rightTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(rightSubtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Image(systemName: rightIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(isHovering ? tint.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
    }
}

private struct GeminiAgentStatusDualPill: View {
    let voice: String
    let thinking: String
    let tint: Color
    let lang: String
    
    var body: some View {
        GeminiDualPill(
            leftIcon: "waveform",
            leftTitle: voice,
            leftSubtitle: Localization.get("Giọng nói", lang: lang),
            rightIcon: "sparkles",
            rightTitle: thinking,
            rightSubtitle: Localization.get("Suy nghĩ", lang: lang),
            tint: tint
        )
    }
}

struct GeminiTalkPanelCard<Content: View>: View {
    let tint: Color?
    let content: Content

    init(
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.085),
                                Color.white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint?.opacity(0.28) ?? Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct GeminiTalkStateBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(tint.opacity(0.16))
        )
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
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
        VStack(spacing: 10) {
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
    }

    private var setupHomeContent: some View {
        HStack(alignment: .center, spacing: 32) { 
            HStack(alignment: .center, spacing: 32) { // Increased spacing to avoid wave overlap
                Button {
                    setupViewMode = .agentSelection
                } label: {
                    GeminiAgentHomeAvatarFigure(
                        statusColor: statusColor,
                        avatarSymbolName: selectedAgentAvatarSymbolName,
                        avatarImageURL: selectedAgentAvatarImageURL
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(formattedAgentDisplayName(gemini.selectedSystemPromptPreset.title))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(themeAccent)
                        }

                        HStack(spacing: 4) {
                            Text(Localization.get("Online", lang: appLanguage))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Circle()
                                .fill(themeAccent)
                                .frame(width: 5, height: 5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GeminiAgentStatusDualPill(
                            voice: gemini.selectedVoice.rawValue,
                            thinking: gemini.thinkingLevel.rawValue,
                            tint: themeAccent,
                            lang: appLanguage
                        )
                        
                        GeminiDualPill(
                            leftIcon: "wrench.fill",
                            leftTitle: "\(gemini.enabledTools.count) \(Localization.get("Công cụ", lang: appLanguage))",
                            leftSubtitle: Localization.get("Được sử dụng", lang: appLanguage),
                            rightIcon: "sparkles",
                            rightTitle: "\(gemini.enabledSkillNames.count) \(Localization.get("Kỹ năng", lang: appLanguage))",
                            rightSubtitle: Localization.get("Sẵn sàng hỗ trợ", lang: appLanguage),
                            tint: themeAccent
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12) // Move right away from edge

            Button {
                gemini.toggleConnection()
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                gemini.lifecycleState.isBusy ?
                                Color.red.opacity(0.15) :
                                themeAccent.opacity(0.15)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: gemini.lifecycleState.isBusy ? "stop.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(gemini.lifecycleState.isBusy ? .red : themeAccent)
                            .shadow(color: (gemini.lifecycleState.isBusy ? Color.red : themeAccent).opacity(0.5), radius: 8)
                    }
                    
                    VStack(spacing: 1) {
                        Text(gemini.lifecycleState.isBusy
                            ? Localization.get("Dừng", lang: appLanguage)
                            : Localization.get("Kết nối", lang: appLanguage))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                        
                        Text(gemini.lifecycleState.isBusy
                            ? Localization.get("Kết thúc", lang: appLanguage)
                            : Localization.get("Bắt đầu", lang: appLanguage))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background {
                    ZStack {
                        // Glass background
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(0.03))
                        
                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.15),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(GrowingButtonStyle())
            .disabled(!gemini.canStartConnection && !gemini.lifecycleState.isBusy)
            .frame(width: 86)
            .padding(.trailing, 12) // Move left away from edge
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        AppSettingsController.shared.open(tab: .talk)
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


struct GeminiExecApprovalCard: View {
    let request: ExecApprovalRequest
    let queueCount: Int
    let onApproveOnce: () -> Void
    let onApproveExact: () -> Void
    let onApproveFamily: () -> Void
    let onDeny: () -> Void
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemOrange).ensureMinimumBrightness(factor: 0.75))
                    Text("\(Localization.get("Approve", lang: appLanguage)) (\(Int(request.timeoutSeconds))s)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.86))
                    Spacer()
                    if queueCount > 1 {
                        Text("\(queueCount) queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.42))
                    }
                }

                Text(request.command)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                if let workingDirectory = request.workingDirectory,
                   !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("cwd: \(workingDirectory)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 8) {
                GeminiPillButton(
                    title: Localization.get("Deny", lang: appLanguage),
                    tint: Color(nsColor: .systemRed).opacity(0.85),
                    fillsAvailableWidth: true
                ) {
                    onDeny()
                }
                
                GeminiPillButton(
                    title: Localization.get("Once", lang: appLanguage),
                    tint: Color(nsColor: .systemBlue),
                    fillsAvailableWidth: true
                ) {
                    onApproveOnce()
                }
                
                GeminiPillButton(
                    title: Localization.get("Exact", lang: appLanguage),
                    tint: Color(nsColor: .systemGreen),
                    fillsAvailableWidth: true
                ) {
                    onApproveExact()
                }
                
                if let family = request.commandFamily {
                    GeminiPillButton(
                        title: "\(Localization.get("Always", lang: appLanguage)) \(family)",
                        tint: Color(nsColor: .systemTeal),
                        fillsAvailableWidth: true
                    ) {
                        onApproveFamily()
                    }
                }
            }
            .frame(width: 110)
        }
        .padding(.vertical, 4)
    }
}


struct GeminiAgentAvatarArtwork: View {
    let imageURL: URL?
    let symbolName: String
    let symbolFont: Font
    let size: CGFloat

    @State private var loadedImage: NSImage?

    private static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 20
        return cache
    }()

    private static func loadImageAsync(from url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        // Move file read off the main thread
        let image = await Task.detached {
            NSImage(contentsOf: url)
        }.value
        
        if let image {
            imageCache.setObject(image, forKey: key)
        }
        return image
    }

    var body: some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .clipped()
            } else {
                Image(systemName: symbolName)
                    .font(symbolFont)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size, height: size)
            }
        }
        .task(id: imageURL) {
            guard let imageURL else {
                loadedImage = nil
                return
            }
            if let cached = Self.imageCache.object(forKey: imageURL as NSURL) {
                loadedImage = cached
            } else {
                loadedImage = await Self.loadImageAsync(from: imageURL)
            }
        }
    }
}

struct GeminiFileTextEditor: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var isLightChrome: Bool { colorScheme == .light }
    private var fillColor: Color { isLightChrome ? .black.opacity(0.04) : .white.opacity(0.08) }
    private var strokeColor: Color { isLightChrome ? .black.opacity(0.1) : .white.opacity(0.12) }
    private var textColor: Color { isLightChrome ? .black.opacity(0.9) : .white.opacity(0.9) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)

            RoundedRectangle(cornerRadius: 10)
                .stroke(strokeColor, lineWidth: 1)

            TextEditor(text: $text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(textColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(minHeight: 180)
    }
}

struct GeminiActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        StandardActionButton(
            title: title,
            icon: icon,
            tint: tint,
            variant: .primary,
            action: action
        )
    }
}

/// Shared pill chrome for live controls (`GeminiControlToggle`, screen share picker).
private struct GeminiControlPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var activeTint: Color {
        isDestructive ? Color(nsColor: .systemRed) : themedNotchAccentColor(from: accentColorID)
    }

    private var foregroundColor: Color {
        if isDestructive {
            return .white.opacity(0.96)
        }
        return isActive ? .black.opacity(0.84) : .white.opacity(0.78)
    }

    private var backgroundFill: Color {
        isActive ? activeTint : GeminiPanelControlPalette.liveInactiveFill
    }

    private var shadowColor: Color {
        isActive ? .black.opacity(0.12) : .clear
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(NotchPanelFieldMetrics.labelFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)
            Text(label)
                .font(NotchPanelFieldMetrics.labelFont)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
        .background(
            Capsule()
                .fill(backgroundFill)
                .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
        )
        .overlay {
            if !isActive {
                Capsule()
                    .stroke(GeminiPanelControlPalette.liveInactiveStroke, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct GeminiControlToggle: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeminiControlPill(icon: icon, label: label, isActive: isActive, isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
    }
}


struct GeminiTranscriptModeToggle: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var mode: GeminiLiveViewModel.TranscriptOverlayMode {
        gemini.transcriptOverlayMode
    }

    private var icon: String {
        "captions.bubble"
    }

    private var label: String {
        switch mode {
        case .autoHide:
            return Localization.get("Auto Hide", lang: appLanguage)
        case .pinned:
            return Localization.get("Pin", lang: appLanguage)
        case .hidden:
            return Localization.get("Off", lang: appLanguage)
        }
    }

    private var isActive: Bool {
        mode != .hidden
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: icon, label: label, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                transcriptRow(Localization.get("Auto Hide", lang: appLanguage)) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = true
                    isPickerOpen = false
                }
                transcriptRow(Localization.get("Pin", lang: appLanguage)) {
                    gemini.showTranscriptOverlay = true
                    gemini.transcriptOverlayAutoHide = false
                    isPickerOpen = false
                }
                Divider()
                    .padding(.vertical, 4)
                transcriptRow(Localization.get("Off", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                    gemini.setTranscriptOverlayEnabled(false)
                    isPickerOpen = false
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func transcriptRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GeminiInputModeMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var icon: String {
        switch gemini.inputMode {
        case .openMic:
            return "mic.fill"
        case .pushToTalk:
            return "hand.tap.fill"
        }
    }

    private var title: String {
        switch gemini.inputMode {
        case .openMic:
            return Localization.get("Mic", lang: appLanguage)
        case .pushToTalk:
            if gemini.canDisconnectSession {
                return gemini.holdToTalkShortcut.displayString
            }
            return Localization.get("Push to Talk", lang: appLanguage)
        }
    }

    private var isActive: Bool {
        switch gemini.inputMode {
        case .openMic:
            return gemini.isMicrophoneEnabled
        case .pushToTalk:
            return true
        }
    }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: icon, label: title, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                inputModeRow(Localization.get("Open Mic", lang: appLanguage)) {
                    gemini.setInputMode(.openMic)
                    gemini.setOpenMicrophoneEnabled(true)
                    isPickerOpen = false
                }
                inputModeRow(Localization.get("Push to Talk", lang: appLanguage)) {
                    gemini.setInputMode(.pushToTalk)
                    isPickerOpen = false
                }
                Divider()
                    .padding(.vertical, 4)
                inputModeRow(Localization.get("Mute Mic", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                    gemini.setInputMode(.openMic)
                    gemini.setOpenMicrophoneEnabled(false)
                    isPickerOpen = false
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func inputModeRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GeminiScreenShareMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    @State private var isPickerOpen = false
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var isActive: Bool { gemini.isScreenSharingEnabled }

    var body: some View {
        Button {
            isPickerOpen.toggle()
        } label: {
            GeminiControlPill(icon: gemini.screenSharingIcon, label: gemini.screenSharingLabel, isActive: isActive)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                screenShareRow(Localization.get("Share Full Screen", lang: appLanguage)) {
                    gemini.startFullScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow(Localization.get("Share Selected Region", lang: appLanguage)) {
                    gemini.startRegionScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow(Localization.get("Share App Window", lang: appLanguage)) {
                    gemini.startWindowSharing()
                    isPickerOpen = false
                }
                if gemini.isScreenSharingEnabled {
                    Divider()
                        .padding(.vertical, 4)
                    screenShareRow(Localization.get("Stop Sharing", lang: appLanguage), foreground: Color(nsColor: .systemRed)) {
                        gemini.stopScreenSharing()
                        isPickerOpen = false
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 200)
        }
        .onChange(of: isPickerOpen) { _, isOpen in
            presentationModel.setAutoCollapseSuppressed(isOpen, reason: .talkPopover)
        }
    }

    private func screenShareRow(_ title: String, foreground: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GeminiOutputVolumeControl: View {
    @Binding var value: Double

    private var icon: String {
        if value <= 0.001 {
            return "speaker.slash.fill"
        }
        if value < 0.34 {
            return "speaker.1.fill"
        }
        if value < 0.67 {
            return "speaker.2.fill"
        }
        return "speaker.3.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(NotchPanelFieldMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: NotchPanelFieldMetrics.iconColWidth, alignment: .center)

            Slider(value: $value, in: 0...1)
                .controlSize(.small)
                .tint(.white.opacity(0.9))
                .frame(width: 72)
        }
        .padding(.horizontal, NotchPanelFieldMetrics.hPad)
        .padding(.vertical, NotchPanelFieldMetrics.vPad)
        .frame(minHeight: NotchPanelFieldMetrics.minHeight)
        .background(
            Capsule()
                .fill(GeminiPanelControlPalette.liveInactiveFill)
        )
        .overlay {
            Capsule()
                .stroke(GeminiPanelControlPalette.liveInactiveStroke, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

struct GeminiSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        StandardActionButton(
            title: title,
            icon: nil,
            tint: .white,
            variant: .primary,
            action: action
        )
    }
}

struct GeminiTranscriptCard: View {
    let title: String
    let text: String
    let placeholder: String
    var revealsProgressively = false
    var showsFullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(showsFullText ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        if revealsProgressively {
                            ProgressiveRevealText(text: text, animateOnAppear: false)
                        } else {
                            Text(text)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(showsFullText ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct GeminiDropdownPicker<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let label: String
    /// Leading SF Symbol; matches other Gemini menus (prompt, tools).
    var leadingIcon: String = "slider.horizontal.3"
    @Binding var selection: T
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var buttonTitle: String {
        "\(label): \(Localization.get(selection.rawValue, lang: appLanguage))"
    }

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(Localization.get(item.rawValue, lang: appLanguage), systemImage: "checkmark")
                    } else {
                        Text(Localization.get(item.rawValue, lang: appLanguage))
                    }
                }
            }
        } label: {
            NotchMenuFieldRow(leadingIcon: leadingIcon, title: buttonTitle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiPillPicker<T: RawRepresentable & CaseIterable & Hashable>: View
where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let title: String
    let icon: String // e.g. "speaker.fill"
    let tint: Color // e.g. Color.yellow
    @Binding var selection: T
    let displayText: (T) -> String
    @AppStorage("app_language") private var appLanguage: String = "English"

    init(
        title: String,
        icon: String,
        tint: Color,
        selection: Binding<T>,
        displayText: @escaping (T) -> String = { $0.rawValue }
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        _selection = selection
        self.displayText = displayText
    }

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(Localization.get(displayText(item), lang: appLanguage), systemImage: "checkmark")
                    } else {
                        Text(Localization.get(displayText(item), lang: appLanguage))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localization.get(displayText(selection), lang: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                    if !title.isEmpty {
                        Text(Localization.get(title, lang: appLanguage))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct GeminiPillButton: View {
    let title: String
    var icon: String? = nil
    let tint: Color
    var isDisabled: Bool = false
    /// Expands each pill to equal width inside a shared `HStack` row (e.g. 2×2 grid).
    var fillsAvailableWidth: Bool = false
    let action: () -> Void

    var body: some View {
        StandardActionButton(
            title: title,
            icon: icon,
            tint: tint,
            variant: .primary,
            isDisabled: isDisabled,
            fillsAvailableWidth: fillsAvailableWidth,
            action: action
        )
    }
}

struct GeminiToolsPicker: View {
    @Binding var selection: Set<GeminiTool>
    var lockedTools: Set<GeminiTool> = []
    var isDisabled = false
    @State private var showExecWarning = false
    @State private var showFDAWarning = false
    @State private var pendingFDATool: GeminiTool?
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSelectableTools: Set<GeminiTool> {
        Set(GeminiTool.coreCases).union(GeminiTool.restrictedTools).subtracting(lockedTools)
    }

    private var hasAllToolsSelected: Bool {
        selection.isSuperset(of: allSelectableTools)
    }

    private var allToolsList: [GeminiTool] {
        GeminiTool.coreCases + GeminiTool.restrictedTools.subtracting(GeminiTool.coreToolSet).sorted { $0.rawValue < $1.rawValue }
    }

    private var summaryText: String {
        let effectiveCount = selection.union(lockedTools).count
        switch effectiveCount {
        case 0:
            return Localization.get("No tools", lang: appLanguage)
        case GeminiTool.coreCases.count:
            return Localization.get("All tools", lang: appLanguage)
        default:
            return "\(effectiveCount) \(Localization.get("tools", lang: appLanguage))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Localization.get("Core Tools", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                Button {
                    if hasAllToolsSelected {
                        selection = []
                    } else {
                        selection = allSelectableTools
                    }
                } label: {
                    Text(Localization.get(hasAllToolsSelected ? "Disable All" : "Enable All", lang: appLanguage))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeAccent)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            .padding(.bottom, 2)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(allToolsList) { tool in
                    let isLocked = lockedTools.contains(tool)
                    let isSelected = selection.contains(tool) || isLocked
                    
                    HStack(spacing: 8) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 14)
                            .foregroundStyle(isSelected ? themeAccent : .white.opacity(0.4))
                        
                        Text(Localization.get(tool.displayName, lang: appLanguage))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                            .lineLimit(1)
                        
                        Spacer(minLength: 0)
                        
                        Toggle("", isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                guard !isLocked else { return }
                                if newValue {
                                    if GeminiTool.restrictedTools.contains(tool) {
                                        showExecWarning = true
                                        return
                                    }
                                    if tool == .appleMail || tool == .localFileSearch {
                                        if !SystemPermissionsManager.shared.hasFullDiskAccess() {
                                            pendingFDATool = tool
                                            showFDAWarning = true
                                            return
                                        }
                                    }
                                    selection.insert(tool)
                                } else {
                                    selection.remove(tool)
                                }
                            }
                        ))
                        .toggleStyle(NotchSwitchStyle(tint: themeAccent))
                        .disabled(isLocked || isDisabled)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? themeAccent.opacity(0.18) : Color.clear, lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .alert("⚠️ Enable Shell Access?", isPresented: $showExecWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Enable", role: .destructive) {
                selection.insert(.exec)
            }
        } message: {
            Text("Exec allows the AI to run arbitrary shell commands on your Mac. This is risky in a voice conversation — the AI may execute commands you don't expect. Only enable this if you fully understand the risks.")
        }
        .alert("🔒 Full Disk Access Required", isPresented: $showFDAWarning) {
            Button("Cancel", role: .cancel) {
                pendingFDATool = nil
            }
            Button("Open System Settings") {
                SystemPermissionsManager.shared.openFullDiskAccessSettings()
                // We don't insert yet because they haven't granted it yet.
                // They'll need to toggle again after granting.
                pendingFDATool = nil
            }
        } message: {
            let toolName = pendingFDATool?.displayName ?? "This tool"
            Text("\(toolName) requires Full Disk Access to read local data. Please add Notch to the Full Disk Access list in System Settings > Privacy & Security.")
        }
    }
}

struct NotchSwitchStyle: ToggleStyle {
    var tint: Color = Color.blue

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Rectangle()
                .fill(configuration.isOn ? tint : Color.white.opacity(0.1))
                .frame(width: 24, height: 14)
                .overlay(
                    Circle()
                        .fill(.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 5 : -5)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
                .cornerRadius(7)
        }
    }
}

struct GeminiSkillsPicker: View {
    let installedSkills: [InstalledSkill]
    var userSkillNames: Set<String> = []
    @Binding var selection: Set<String>
    var isDisabled = false
    var onImport: (() -> Void)? = nil
    var onDeleteName: ((String) -> Void)? = nil
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSkillNames: Set<String> {
        Set(installedSkills.map(\.metadata.name))
    }

    private var hasAllSkillsSelected: Bool {
        !installedSkills.isEmpty && selection.isSuperset(of: allSkillNames)
    }

    private var sortedSkills: [InstalledSkill] {
        installedSkills.sorted { s1, s2 in
            let isU1 = userSkillNames.contains(s1.metadata.name)
            let isU2 = userSkillNames.contains(s2.metadata.name)
            if isU1 != isU2 {
                return isU1 // User skills first
            }
            return s1.metadata.name < s2.metadata.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(Localization.get("Skills", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                
                Spacer()

                if let onImport = onImport {
                    Button(action: onImport) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(Localization.get("New Skill", lang: appLanguage))
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                }
                
                Button {
                    if hasAllSkillsSelected {
                        selection = []
                    } else {
                        selection = allSkillNames
                    }
                } label: {
                    Text(Localization.get(hasAllSkillsSelected ? "Disable All" : "Enable All", lang: appLanguage))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            if installedSkills.isEmpty {
                Text(Localization.get("No skills installed", lang: appLanguage))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ForEach(sortedSkills, id: \.metadata.name) { skill in
                    let isSelected = selection.contains(skill.metadata.name)
                    let isUserSkill = userSkillNames.contains(skill.metadata.name)
                    
                    HStack(spacing: 8) {
                        Image(systemName: skill.metadata.icon)
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 14)
                            .foregroundStyle(isSelected ? themeAccent : .white.opacity(0.4))
                        
                        Text(skill.metadata.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                        
                        if isUserSkill {
                            Text("User")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(themeAccent.opacity(0.2))
                                .cornerRadius(4)
                        }

                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                if newValue {
                                    selection.insert(skill.metadata.name)
                                } else {
                                    selection.remove(skill.metadata.name)
                                }
                            }
                        ))
                        .toggleStyle(NotchSwitchStyle(tint: themeAccent))
                        .disabled(isDisabled)

                        if isUserSkill, let onDeleteName = onDeleteName {
                            Button {
                                onDeleteName(skill.metadata.name)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeminiSkillManagementMenu: View {
    let installedSkills: [InstalledSkill]
    let isDisabled: Bool
    let onImport: () -> Void
    let onDelete: (InstalledSkill) -> Void
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    var body: some View {
        Menu {
            Button(action: onImport) {
                Label(Localization.get("Add Skill", lang: appLanguage), systemImage: "plus")
            }

            Divider()

            if installedSkills.isEmpty {
                Text(Localization.get("No user skills", lang: appLanguage))
            } else {
                ForEach(installedSkills, id: \.metadata.name) { skill in
                    Button(role: .destructive) {
                        onDelete(skill)
                    } label: {
                        Label("\(Localization.get("Delete", lang: appLanguage)) \(skill.metadata.name)", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                Text(Localization.get("Manage skills", lang: appLanguage))
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.5))
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(themeAccent)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Avatar only (used as `Menu` label). Agent name is shown as a label below.
struct GeminiAgentHomeAvatarFigure: View {
    let statusColor: Color
    var avatarSymbolName: String = GeminiSystemPromptPreset.defaultAvatarSymbolName
    var avatarImageURL: URL? = nil
    @State private var animPhase: Double = 0
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Modern Waveform Visualizer (Behind Avatar)
            HStack(spacing: 102) { // Tighter gap
                waveformGroup(isLeft: true)
                waveformGroup(isLeft: false)
            }
            .frame(width: 200)
            .opacity(isHovering ? 1.0 : 0.8)
            .blur(radius: 0.5)

            // Inner Shadow/Glow for the Avatar
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 100, height: 100)
                .shadow(color: statusColor.opacity(isHovering ? 0.7 : 0.4), radius: isHovering ? 25 : 15)

            // Avatar Container
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 94, height: 94)
                    .overlay {
                        Circle()
                            .stroke(statusColor.opacity(isHovering ? 0.5 : 0.3), lineWidth: isHovering ? 2 : 1.5)
                            .frame(width: 94, height: 94)
                    }

                GeminiAgentAvatarArtwork(
                    imageURL: avatarImageURL,
                    symbolName: avatarSymbolName,
                    symbolFont: .system(size: 36, weight: .medium),
                    size: 94
                )
                .clipShape(Circle())
            }
        }
        .scaleEffect(isHovering ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .frame(width: 108, height: 100, alignment: .top)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animPhase = 1.0
            }
        }
    }

    @ViewBuilder
    private func waveformGroup(isLeft: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(statusColor)
                    .frame(width: 2, height: heightForBar(i, isLeft: isLeft))
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
            }
        }
    }

    private func heightForBar(_ index: Int, isLeft: Bool) -> CGFloat {
        // Tapering off from avatar: [24, 16, 10, 6, 3]
        let heights: [CGFloat] = [24, 16, 10, 6, 3]
        
        let baseH: CGFloat
        if isLeft {
            // Left group: index 4 is closest to the avatar (right-most in group)
            baseH = heights[4 - index]
        } else {
            // Right group: index 0 is closest to the avatar (left-most in group)
            baseH = heights[index]
        }
        return baseH + (animPhase * 3)
    }
}

struct GeminiAgentSelectionView: View {
    let prompts: [GeminiSystemPromptPreset]
    let selectedID: String
    let statusColor: Color
    let onSelect: (String) -> Void
    let onCreate: () -> Void
    let onDone: () -> Void

    @AppStorage("app_language") private var appLanguage: String = "English"
    @State private var currentPage: Int = 0

    private let pageSize = 5

    private var totalItems: Int {
        prompts.count + 1 // +1 for the "New Agent" button
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(totalItems) / Double(pageSize))))
    }

    private var currentIndices: Range<Int> {
        let start = currentPage * pageSize
        let end = min(start + pageSize, totalItems)
        return start..<end
    }

    private var isLastPage: Bool { currentPage == totalPages - 1 }

    private let columns = [
        GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Agent grid — fixed size so it naturally expands parent
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(currentIndices, id: \.self) { index in
                    if index < prompts.count {
                        let prompt = prompts[index]
                        AgentSelectionCard(
                            prompt: prompt,
                            isSelected: prompt.id == selectedID,
                            statusColor: statusColor,
                            action: { onSelect(prompt.id) }
                        )
                    } else {
                        // "New Agent" button is always the very last item overall
                        Button(action: onCreate) {
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                        .frame(width: 58, height: 58)

                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                                .frame(width: 74, height: 74)

                                Text(Localization.get("New Agent", lang: appLanguage))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.42))
                                    .lineLimit(1)
                                    .tracking(0.2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)

            Spacer(minLength: 0)

            // Pagination controls — only shown when needed
            if totalPages > 1 {
                HStack(spacing: 12) {
                    // Prev button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            currentPage = max(0, currentPage - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(currentPage == 0 ? .white.opacity(0.2) : .white.opacity(0.75))
                            .frame(width: 24, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(currentPage == 0 ? 0.04 : 0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentPage == 0)

                    // Page dots
                    HStack(spacing: 5) {
                        ForEach(0..<totalPages, id: \.self) { idx in
                            Circle()
                                .fill(idx == currentPage ? statusColor : Color.white.opacity(0.22))
                                .frame(width: idx == currentPage ? 6 : 4, height: idx == currentPage ? 6 : 4)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Next button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            currentPage = min(totalPages - 1, currentPage + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isLastPage ? .white.opacity(0.2) : .white.opacity(0.75))
                            .frame(width: 24, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(isLastPage ? 0.04 : 0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLastPage)
                }
                .padding(.top, 0)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .onChange(of: prompts.count) { _, _ in
            // Clamp page if agents were deleted
            currentPage = min(currentPage, max(0, totalPages - 1))
        }
    }
}

struct AgentSelectionCard: View {
    let prompt: GeminiSystemPromptPreset
    let isSelected: Bool
    let statusColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 74, height: 74)
                            .blur(radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [statusColor.opacity(0.9), statusColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 58, height: 58)
                        .overlay {
                            Circle()
                                .stroke(isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                        }
                        .shadow(color: isSelected ? statusColor.opacity(0.3) : .clear, radius: 8, y: 4)

                    GeminiAgentAvatarArtwork(
                        imageURL: prompt.resolvedAvatarImageURL,
                        symbolName: prompt.resolvedAvatarSymbolName,
                        symbolFont: .system(size: 22, weight: .medium),
                        size: 58
                    )
                    
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(statusColor).padding(1))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .frame(width: 58, height: 58)
                    }
                }
                .frame(width: 74, height: 74)
                
                Text(formattedAgentDisplayName(prompt.title))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.82))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
                    .frame(height: 28, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}
