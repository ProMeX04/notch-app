import AppKit
import SwiftUI

private enum GeminiPanelControlPalette {
    static let liveInactiveFill = Color.white.opacity(0.08)
    static let liveInactiveStroke = Color.white.opacity(0.08)
}

private func themedNotchAccentColor(from accentColorID: String) -> Color {
    NotchAccentColorOption.resolve(rawValue: accentColorID).brightColor
}

/// Invisible caption line so a bare button aligns with labeled pickers in setup rows.
private struct GeminiSetupCaptionSpacer: View {
    var body: some View {
        Text("\u{00a0}")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.clear)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 13, alignment: .leading)
    }
}

private func formattedAgentDisplayName(_ raw: String) -> String {
    let collapsed = raw
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return collapsed.isEmpty ? "Untitled Agent" : collapsed
}

enum GeminiPromptEditorMode: Equatable {
    case create
    case edit(String)
    case user
    case memory
}

private enum GeminiSetupViewMode: Equatable {
    case home
    case agentSettings
    case agentSelection
}

private enum GeminiAgentSettingsTab: String, CaseIterable, Identifiable {
    case common = "Common"
    case prompt = "Profile"
    case tools = "Tools"
    case skills = "Skills"
    var id: String { rawValue }
}

private struct GeminiAgentCommonSettingsContent: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @Binding var holdShortcut: HoldToTalkShortcut
    let themeAccent: Color
    let openSettings: () -> Void
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var isUsingAPIKey: Bool {
        gemini.selectedConnectionMethod == .userAPIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard(
                title: "Gemini",
                subtitle: "Choose how Notch connects to Gemini Live"
            ) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(GeminiLiveConnectionMethod.allCases) { method in
                            Button {
                                gemini.selectedConnectionMethod = method
                            } label: {
                                Text(method.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(
                                        gemini.selectedConnectionMethod == method
                                            ? .black.opacity(0.84)
                                            : .white.opacity(0.72)
                                    )
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule()
                                            .fill(
                                                gemini.selectedConnectionMethod == method
                                                    ? themeAccent
                                                    : Color.white.opacity(0.08)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isUsingAPIKey {
                        HStack(spacing: 8) {
                            Text("Key")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.32))
                                .frame(width: 55, alignment: .leading)

                            SecureField(
                                "AIza...",
                                text: $gemini.apiKeyText,
                                onCommit: { Task { await gemini.saveAPIKey() } }
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)

                            if !gemini.apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    Task { await gemini.saveAPIKey() }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(themeAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("Account")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.32))
                                .frame(width: 55, alignment: .leading)

                            Text(gemini.backendSignedInSummary.map { "Signed in as \($0)" } ?? "Sign in required")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(gemini.isBackendAuthenticated ? .white.opacity(0.88) : .white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(Localization.get("Open Settings Tab", lang: appLanguage)) {
                                openSettings()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(themeAccent)
                        }
                    }

                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
            }

            settingsCard(title: nil, subtitle: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    HoldToTalkShortcutRecorderView(
                        shortcut: $holdShortcut,
                        title: Localization.get("Push to Talk", lang: appLanguage),
                        helperText: nil,
                        isNotchStyle: true,
                        tint: themeAccent
                    )
                    Text(Localization.get("Push to Talk hint", lang: appLanguage))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func settingsCard<Content: View>(title: String?, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if (title != nil && !title!.isEmpty) || (subtitle != nil && !subtitle!.isEmpty) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct GeminiTalkPromptEditorView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @Binding var title: String
    @Binding var content: String
    let isEditing: Bool
    let onDone: () -> Void

    var body: some View {
        GeminiPromptEditorCard(
            title: $title,
            content: $content,
            isEditing: isEditing,
            onDone: onDone
        )
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

                Spacer()

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

private struct GeminiTalkProLockedView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let appLanguage: String
    let themeAccent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mua Notch Pro để sử dụng")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            GeminiActionButton(
                title: Localization.get("Buy Notch Pro", lang: appLanguage),
                icon: "sparkles",
                tint: themeAccent
            ) {
                gemini.openWebProCheckout()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct GeminiTalkDisconnectedHomeView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @Binding var setupViewMode: GeminiSetupViewMode
    @Binding var settingsTab: GeminiAgentSettingsTab
    @Binding var holdShortcut: HoldToTalkShortcut
    @Binding var agentNameDraft: String
    let isAgentNameFieldFocused: FocusState<Bool>.Binding
    let appLanguage: String
    let themeAccent: Color
    let statusColor: Color
    let selectedAgentAvatarSymbolName: String
    let selectedAgentAvatarImageURL: URL?
    let openSettingsPanel: () -> Void
    let beginCreatingAgent: () -> Void
    let beginEditingSelectedPrompt: () -> Void
    let beginEditingUserProfile: () -> Void
    let beginEditingMemory: () -> Void
    let requestDeleteSelectedPrompt: () -> Void
    let saveAgentNameDraft: () -> Void
    let chooseSelectedSystemPromptAvatarImage: () -> Void
    let clearSelectedSystemPromptAvatarImage: () -> Void

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
                case .agentSettings:
                    agentSettingsView
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
            } else if gemini.isSavingAPIKey {
                Text(gemini.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var setupHomeContent: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 2) {
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

                Text(formattedAgentDisplayName(gemini.selectedSystemPromptPreset.title))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.center)
                    .frame(width: 136)
                    .frame(minHeight: 28, alignment: .top)
            }
            .frame(width: 130)

            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(themeAccent)
                        Text("\(gemini.enabledTools.count) \(Localization.get("Tools", lang: appLanguage))")
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(themeAccent)
                        Text("\(gemini.enabledSkillNames.count) \(Localization.get("Skills", lang: appLanguage))")
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 2)
                .padding(.bottom, 4)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        GeminiPillPicker(
                            title: "",
                            icon: "cpu",
                            tint: themeAccent,
                            selection: $gemini.selectedModel,
                            displayText: \.displayName
                        )

                        GeminiPillPicker(
                            title: "",
                            icon: "waveform",
                            tint: themeAccent,
                            selection: $gemini.selectedVoice
                        )

                        GeminiPillPicker(
                            title: "",
                            icon: "gearshape.2.fill",
                            tint: themeAccent,
                            selection: $gemini.thinkingLevel
                        )
                    }

                    HStack(spacing: 8) {
                        GeminiPillButton(
                            title: Localization.get("Settings", lang: appLanguage),
                            icon: "slider.horizontal.3",
                            tint: themeAccent
                        ) {
                            setupViewMode = .agentSettings
                        }

                        GeminiPillButton(
                            title: gemini.connectionState == .connecting
                                ? Localization.get("Cancel", lang: appLanguage)
                                : Localization.get(gemini.connectionButtonTitle, lang: appLanguage),
                            icon: gemini.connectionState == .connecting
                                ? "xmark.circle.fill"
                                : gemini.connectionButtonIcon,
                            tint: gemini.connectionState == .connecting
                                ? Color(nsColor: .systemRed)
                                : themeAccent
                        ) {
                            gemini.toggleConnection()
                        }
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var noGeminiKeySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(gemini.selectedConnectionSetupTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(gemini.selectedConnectionSetupDescription)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            GeminiActionButton(
                title: gemini.selectedConnectionManageButtonTitle,
                icon: "key.fill",
                tint: themeAccent
            ) {
                openSettingsPanel()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var agentSettingsView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(GeminiAgentSettingsTab.allCases) { tab in
                    Button {
                        settingsTab = tab
                    } label: {
                        Text(Localization.get(tab.rawValue, lang: appLanguage))
                            .font(StandardButtonMetrics.font)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(settingsTab == tab ? .black.opacity(0.85) : .white.opacity(0.85))
                            .padding(.horizontal, 7)
                            .frame(maxWidth: .infinity, minHeight: StandardButtonMetrics.height, alignment: .leading)
                            .background(
                                Group {
                                    if settingsTab == tab {
                                        StandardPrimaryPillChrome(tint: themeAccent)
                                    } else {
                                        Capsule().fill(Color.white.opacity(0.1))
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }

                StandardActionButton(
                    title: Localization.get("Done", lang: appLanguage),
                    tint: themeAccent,
                    variant: .primary,
                    fillsAvailableWidth: true
                ) {
                    setupViewMode = .home
                }
            }
            .frame(width: 92, alignment: .top)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    switch settingsTab {
                    case .common:
                        GeminiAgentCommonSettingsContent(
                            gemini: gemini,
                            holdShortcut: $holdShortcut,
                            themeAccent: themeAccent,
                            openSettings: openSettingsPanel
                        )

                    case .prompt:
                        VStack(alignment: .leading, spacing: 8) {
                            GeminiAgentSummaryCard(
                                statusColor: statusColor,
                                name: $agentNameDraft,
                                avatarSymbolName: selectedAgentAvatarSymbolName,
                                avatarImageURL: selectedAgentAvatarImageURL,
                                nameFieldFocus: isAgentNameFieldFocused,
                                onSubmitName: saveAgentNameDraft,
                                onChooseAvatar: chooseSelectedSystemPromptAvatarImage,
                                onClearAvatar: clearSelectedSystemPromptAvatarImage
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    GeminiPillButton(
                                        title: Localization.get("System Prompt", lang: appLanguage),
                                        icon: "pencil",
                                        tint: themeAccent,
                                        fillsAvailableWidth: true
                                    ) {
                                        beginEditingSelectedPrompt()
                                    }

                                    GeminiPillButton(
                                        title: Localization.get("User Profile", lang: appLanguage),
                                        icon: "person.text.rectangle",
                                        tint: themeAccent,
                                        fillsAvailableWidth: true
                                    ) {
                                        beginEditingUserProfile()
                                    }
                                }

                                HStack(spacing: 8) {
                                    GeminiPillButton(
                                        title: Localization.get("Memory", lang: appLanguage),
                                        icon: "bookmark.fill",
                                        tint: themeAccent,
                                        fillsAvailableWidth: true
                                    ) {
                                        beginEditingMemory()
                                    }

                                    GeminiPillButton(
                                        title: Localization.get("Delete", lang: appLanguage),
                                        icon: "trash",
                                        tint: Color(nsColor: .systemRed).opacity(0.8),
                                        isDisabled: !gemini.canDeleteSelectedSystemPrompt,
                                        fillsAvailableWidth: true
                                    ) {
                                        requestDeleteSelectedPrompt()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    case .tools:
                        GeminiToolsPicker(
                            selection: $gemini.enabledTools,
                            isDisabled: !gemini.canManageSkills
                        )

                    case .skills:
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
                .padding(.trailing, 4)
            }
        }
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
    @ObservedObject var headerAccessoryController: NotchHeaderAccessoryController
    @ObservedObject var presentationModel: NotchPresentationModel
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @State private var setupViewMode: GeminiSetupViewMode = .home
    @State private var settingsTab: GeminiAgentSettingsTab = .prompt
    @State private var holdShortcut = HoldToTalkShortcutStore.load()
    @State private var promptEditorMode: GeminiPromptEditorMode?
    @State private var promptDraftTitle = ""
    @State private var promptDraftContent = ""
    @State private var agentNameDraft = ""
    @FocusState private var isAgentNameFieldFocused: Bool
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
        Color(nsColor: gemini.connectionState.accentColor).ensureMinimumBrightness(factor: 0.72)
    }

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var selectedPromptBinding: Binding<String> {
        Binding(
            get: { gemini.selectedSystemPromptID },
            set: { gemini.selectSystemPrompt(id: $0) }
        )
    }

    private var isPromptEditorPresented: Bool {
        promptEditorMode != nil
    }

    private var selectedAgentAvatarSymbolName: String {
        gemini.selectedSystemPromptAvatarSymbolName
    }

    private var selectedAgentAvatarImageURL: URL? {
        gemini.selectedSystemPromptAvatarImageURL
    }

    @ViewBuilder
    private var systemPromptSection: some View {
        HStack(alignment: .center, spacing: 8) {
            GeminiAgentPicker(
                prompts: gemini.systemPromptPresets,
                selection: selectedPromptBinding
            )
            .frame(maxWidth: .infinity)

            GeminiEditAgentButton(onEdit: beginEditingSelectedPrompt)
                .frame(maxWidth: .infinity)
        }
    }

    private var isEditingExistingPrompt: Bool {
        promptEditorMode != nil && promptEditorMode != .create
    }

    private func beginCreatingAgent() {
        _ = gemini.createSystemPrompt()
        if gemini.hasSavedAPIKey {
            setupViewMode = .agentSettings
        } else {
            openSettingsPanel()
        }
        promptEditorMode = nil
        promptDraftTitle = ""
        promptDraftContent = ""
    }

    private func beginEditingSelectedPrompt() {
        let selectedPrompt = gemini.selectedSystemPromptPreset
        if gemini.hasSavedAPIKey {
            setupViewMode = .agentSettings
        } else {
            openSettingsPanel()
        }
        promptEditorMode = .edit(selectedPrompt.id)
        promptDraftTitle = selectedPrompt.title
        promptDraftContent = selectedPrompt.content
    }

    private func cancelPromptEditing() {
        promptEditorMode = nil
        promptDraftTitle = ""
        promptDraftContent = ""
    }

    private func beginEditingUserProfile() {
        promptEditorMode = .user
        promptDraftTitle = Localization.get("User Profile (USER.md)", lang: appLanguage)
        promptDraftContent = gemini.userProfileContent
    }

    private func beginEditingMemory() {
        promptEditorMode = .memory
        promptDraftTitle = Localization.get("Memory (MEMORY.md)", lang: appLanguage)
        promptDraftContent = gemini.memoryContent
    }

    private func savePromptDraft() {
        guard let mode = promptEditorMode else { return }

        switch mode {
        case .user:
            gemini.saveUserProfile(promptDraftContent)
        case .memory:
            gemini.saveMemory(promptDraftContent)
        case .create, .edit:
            let promptID: String?
            if case let .edit(id) = mode {
                promptID = id
            } else {
                promptID = nil
            }

            guard gemini.saveSystemPrompt(id: promptID, title: promptDraftTitle, content: promptDraftContent) else {
                return
            }
        }

        cancelPromptEditing()
    }

    private func deleteSelectedPrompt() {
        let deletedPromptID = gemini.selectedSystemPromptID
        guard gemini.deleteSelectedSystemPrompt() else { return }

        if case let .edit(id) = promptEditorMode, id == deletedPromptID {
            cancelPromptEditing()
        }

        setupViewMode = .home
    }

    private func requestDeleteSelectedPrompt() {
        guard gemini.canDeleteSelectedSystemPrompt else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Localization.get("Delete Agent?", lang: appLanguage)
        alert.informativeText = Localization.get("Delete \"\(gemini.selectedSystemPromptPreset.title)\"? This can't be undone.", lang: appLanguage)
        alert.addButton(withTitle: Localization.get("Delete", lang: appLanguage))
        alert.addButton(withTitle: Localization.get("Cancel", lang: appLanguage))
        if alert.runModal() == .alertFirstButtonReturn {
            deleteSelectedPrompt()
        }
    }

    private func syncAgentNameDraft() {
        agentNameDraft = gemini.selectedSystemPromptPreset.title
    }

    private func saveAgentNameDraft() {
        gemini.renameSelectedSystemPrompt(to: agentNameDraft)
        agentNameDraft = gemini.selectedSystemPromptPreset.title
    }

    private func refreshHeaderAccessory() {
        headerAccessoryController.clear()
    }

    private func openSettingsPanel() {
        presentationModel.selectPanel(.settings)
    }

    @ViewBuilder
    private var panelContent: some View {
        if isPromptEditorPresented {
            GeminiTalkPromptEditorView(
                gemini: gemini,
                title: $promptDraftTitle,
                content: $promptDraftContent,
                isEditing: isEditingExistingPrompt,
                onDone: savePromptDraft
            )
        } else if gemini.connectionState == .connected {
            GeminiTalkConnectedView(
                gemini: gemini,
                presentationModel: presentationModel,
                appLanguage: appLanguage
            )
        } else if gemini.requiresProForCurrentConnection {
            GeminiTalkProLockedView(
                gemini: gemini,
                appLanguage: appLanguage,
                themeAccent: themeAccent
            )
        } else {
            GeminiTalkDisconnectedHomeView(
                gemini: gemini,
                setupViewMode: $setupViewMode,
                settingsTab: $settingsTab,
                holdShortcut: $holdShortcut,
                agentNameDraft: $agentNameDraft,
                isAgentNameFieldFocused: $isAgentNameFieldFocused,
                appLanguage: appLanguage,
                themeAccent: themeAccent,
                statusColor: statusColor,
                selectedAgentAvatarSymbolName: selectedAgentAvatarSymbolName,
                selectedAgentAvatarImageURL: selectedAgentAvatarImageURL,
                openSettingsPanel: openSettingsPanel,
                beginCreatingAgent: beginCreatingAgent,
                beginEditingSelectedPrompt: beginEditingSelectedPrompt,
                beginEditingUserProfile: beginEditingUserProfile,
                beginEditingMemory: beginEditingMemory,
                requestDeleteSelectedPrompt: requestDeleteSelectedPrompt,
                saveAgentNameDraft: saveAgentNameDraft,
                chooseSelectedSystemPromptAvatarImage: { gemini.chooseSelectedSystemPromptAvatarImage() },
                clearSelectedSystemPromptAvatarImage: { gemini.clearSelectedSystemPromptAvatarImage() }
            )
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            panelContent
            .padding(.bottom, gemini.connectionState == .connected ? 4 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .onAppear(perform: syncAgentNameDraft)
        .onAppear(perform: scheduleHeaderRefresh)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in
            syncAgentNameDraft()
            scheduleHeaderRefresh()
        }
        .onChange(of: isAgentNameFieldFocused) { _, isFocused in
            if !isFocused {
                saveAgentNameDraft()
            }
        }
        .onChange(of: setupViewMode) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: promptEditorMode) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.hasSavedAPIKey) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.connectionState) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: gemini.isSavingAPIKey) { _, _ in
            scheduleHeaderRefresh()
        }
        .onChange(of: promptDraftContent) { _, _ in
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left Column: Command details
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemOrange).ensureMinimumBrightness(factor: 0.75))
                    Text("\(Localization.get("Approve", lang: appLanguage)) (\(Int(request.timeoutSeconds))s)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                    Spacer()
                    if queueCount > 1 {
                        Text("\(queueCount) queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }

                Text(request.command)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }

                if let workingDirectory = request.workingDirectory,
                   !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("cwd: \(workingDirectory)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right Column: Small Actions
            VStack(spacing: 8) {
                GeminiPillButton(
                    title: Localization.get("Deny", lang: appLanguage),
                    tint: Color(nsColor: .systemRed).opacity(0.85)
                ) {
                    onDeny()
                }
                
                GeminiPillButton(
                    title: Localization.get("Once", lang: appLanguage),
                    tint: Color(nsColor: .systemBlue)
                ) {
                    onApproveOnce()
                }
                
                GeminiPillButton(
                    title: Localization.get("Exact", lang: appLanguage),
                    tint: Color(nsColor: .systemGreen)
                ) {
                    onApproveExact()
                }
                
                if let family = request.commandFamily {
                    GeminiPillButton(
                        title: "\(Localization.get("Always", lang: appLanguage)) \(family)",
                        tint: Color(nsColor: .systemTeal)
                    ) {
                        onApproveFamily()
                    }
                }
            }
            .frame(width: 100)
        }
        .padding(.vertical, 4)
    }
}


struct GeminiPromptPicker: View {
    let prompts: [GeminiSystemPromptPreset]
    @Binding var selection: String
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var selectedTitle: String {
        formattedAgentDisplayName(prompts.first(where: { $0.id == selection })?.title ?? prompts.first?.title ?? "Default")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(Localization.get("Agent", lang: appLanguage))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: true, vertical: false)

            Menu {
                ForEach(prompts) { prompt in
                    Button {
                        selection = prompt.id
                    } label: {
                        if prompt.id == selection {
                            Label(formattedAgentDisplayName(prompt.title), systemImage: "checkmark")
                        } else {
                            Text(formattedAgentDisplayName(prompt.title))
                        }
                    }
                }
            } label: {
                NotchMenuFieldRow(leadingIcon: "text.quote", title: selectedTitle)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiAgentPicker: View {
    let prompts: [GeminiSystemPromptPreset]
    @Binding var selection: String
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var selectedTitle: String {
        formattedAgentDisplayName(prompts.first(where: { $0.id == selection })?.title ?? prompts.first?.title ?? "Default")
    }

    private var selectedPrompt: GeminiSystemPromptPreset? {
        prompts.first(where: { $0.id == selection }) ?? prompts.first
    }

    private var selectedAvatarSymbolName: String {
        selectedPrompt?.resolvedAvatarSymbolName
            ?? GeminiSystemPromptPreset.defaultAvatarSymbolName
    }

    private var selectedAvatarImageURL: URL? {
        selectedPrompt?.resolvedAvatarImageURL
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(Localization.get("Agent", lang: appLanguage))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: true, vertical: false)

            Menu {
                ForEach(prompts) { prompt in
                    Button {
                        selection = prompt.id
                    } label: {
                        if prompt.id == selection {
                            Label(formattedAgentDisplayName(prompt.title), systemImage: "checkmark")
                        } else {
                            Text(formattedAgentDisplayName(prompt.title))
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))

                        GeminiAgentAvatarArtwork(
                            imageURL: selectedAvatarImageURL,
                            symbolName: selectedAvatarSymbolName,
                            symbolFont: .system(size: 15, weight: .semibold),
                            size: 22
                        )
                    }
                    .frame(width: 22, height: 22)

                    Text(selectedTitle)
                        .font(NotchPanelFieldMetrics.labelFont)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(NotchPanelFieldMetrics.chevronFont)
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, NotchPanelFieldMetrics.hPad)
                .padding(.vertical, NotchPanelFieldMetrics.vPad)
                .frame(minHeight: NotchPanelFieldMetrics.minHeight)
                .background(
                    RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                        .fill(NotchPanelFieldMetrics.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: NotchPanelFieldMetrics.corner, style: .continuous)
                        .stroke(NotchPanelFieldMetrics.fieldStroke, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct GeminiAgentSummaryCard: View {
    let statusColor: Color
    @Binding var name: String
    let avatarSymbolName: String
    let avatarImageURL: URL?
    let nameFieldFocus: FocusState<Bool>.Binding
    let onSubmitName: () -> Void
    let onChooseAvatar: () -> Void
    let onClearAvatar: () -> Void
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onChooseAvatar) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.78))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(4)
                        .overlay {
                            Circle()
                                .stroke(statusColor.opacity(0.24), lineWidth: 1)
                                .padding(4)
                        }
                    GeminiAgentAvatarArtwork(
                        imageURL: avatarImageURL,
                        symbolName: avatarSymbolName,
                        symbolFont: .system(size: 16, weight: .medium),
                        size: 36
                    )
                }
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            TextField(Localization.get("Name", lang: appLanguage), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .focused(nameFieldFocus)
                .onSubmit(onSubmitName)
        }
        .padding(.vertical, 4)
    }
}

struct GeminiEditAgentButton: View {
    let onEdit: () -> Void
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        Button(action: onEdit) {
            NotchMenuFieldRow(
                leadingIcon: "pencil",
                title: Localization.get("Edit System Prompt", lang: appLanguage)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiPromptEditorCard: View {
    @Binding var title: String
    @Binding var content: String
    let isEditing: Bool
    var showTitle: Bool = true
    let onDone: () -> Void
    
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isEditing {
                TextField(Localization.get("Agent name (optional)", lang: appLanguage), text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                TextEditor(text: $content)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minHeight: 72)

            Button(action: onDone) {
                Text(Localization.get("Done", lang: appLanguage))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(
                        Capsule()
                            .fill(themeAccent)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiFileEditorCard: View {
    let title: String
    let buttonTitle: String
    @Binding var text: String
    let onSave: () -> Void

    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            
            GeminiFileTextEditor(text: $text)
            
            GeminiPillButton(
                title: buttonTitle,
                icon: "square.and.arrow.down",
                tint: themeAccent
            ) {
                onSave()
            }
        }
    }
}

struct GeminiFileTextEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))

            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            TextEditor(text: $text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
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
            if gemini.connectionState == .connected || gemini.connectionState == .connecting {
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
            HStack(spacing: 4) {
                Image(systemName: icon)
                if title.isEmpty {
                    Text(Localization.get(displayText(selection), lang: appLanguage))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                } else {
                    Text("\(Localization.get(title, lang: appLanguage)): \(Localization.get(displayText(selection), lang: appLanguage))")
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .standardPrimaryPillLabelStyle(tint: tint)
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
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue

    private var themeAccent: Color {
        themedNotchAccentColor(from: accentColorID)
    }

    private var allSelectableTools: Set<GeminiTool> {
        Set(GeminiTool.coreCases).subtracting(lockedTools)
    }

    private var hasAllToolsSelected: Bool {
        selection.isSuperset(of: allSelectableTools)
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
                ForEach(GeminiTool.coreCases) { tool in
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
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(isHovering ? 0.45 : 0.28), radius: isHovering ? 18 : 10, y: isHovering ? 8 : 4)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .overlay {
                    Circle()
                        .stroke(statusColor.opacity(isHovering ? 0.34 : 0.18), lineWidth: isHovering ? 1.5 : 1)
                        .frame(width: 96, height: 96)
                }

            GeminiAgentAvatarArtwork(
                imageURL: avatarImageURL,
                symbolName: avatarSymbolName,
                symbolFont: .system(size: 38, weight: .medium),
                size: 104
            )
        }
        .scaleEffect(isHovering ? 1.04 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHovering)
        .frame(width: 120, height: 110, alignment: .top)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
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
