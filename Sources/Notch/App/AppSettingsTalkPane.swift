import SwiftUI

struct AppTalkSettingsPane: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @AppStorage("app_language") private var appLanguage: String = "English"
    @AppStorage(JarvisTalkBackgroundOrbSettings.enabledUserDefaultsKey) private var jarvisOrbBackdropEnabled = true
    @AppStorage(NotchAccentColorOption.storageKey) private var accentColorID: String = NotchAccentColorOption.defaultOption.rawValue
    @State private var holdShortcut = HoldToTalkShortcutStore.load()
    @State private var agentNameDraft = ""
    @State private var agentPromptDraft = ""
    @State private var userProfileDraft = ""
    @State private var memoryDraft = ""
    @State private var showingDeleteAgentAlert = false

    @State private var isUserProfileExpanded = false
    @State private var isMemoryExpanded = false
    @State private var isSystemPromptExpanded = false
    private var tint: Color {
        settingsAccentColor(from: accentColorID)
    }

    private var currentPromptID: String {
        gemini.selectedSystemPromptID
    }

    var body: some View {
        AppSettingsPaneStack {
            AppSettingsPageTitle(
                title: Localization.get("Talk", lang: appLanguage)
            )

            AppSettingsCard(
                title: Localization.get("Connection", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    AppSettingsRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: "network")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint.opacity(0.9))
                                    .frame(width: 28, height: 28)
                                    .background(tint.opacity(0.1).cornerRadius(8))
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
                                .disabled(!gemini.canManageConfiguration)
                            }

                            if gemini.selectedConnectionMethod == .userAPIKey {
                                VStack(alignment: .leading, spacing: 10) {
                                    SecureField("AIza...", text: $gemini.apiKeyText)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(!gemini.canManageConfiguration)

                                    StandardActionButton(
                                        title: gemini.isSavingAPIKey ? Localization.get("Saving...", lang: appLanguage) : Localization.get("Save API key to local", lang: appLanguage),
                                        icon: "key.fill",
                                        tint: tint,
                                        variant: .primary,
                                        isDisabled: gemini.isSavingAPIKey || !gemini.canManageConfiguration
                                    ) {
                                        Task { await gemini.saveAPIKey() }
                                    }
                                }
                            }

                            if gemini.selectedConnectionMethod == .managedServer {
                                VStack(alignment: .leading, spacing: 12) {
                                    #if DEBUG
                                    HStack(spacing: 8) {
                                        Image(systemName: "server.rack")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(tint.opacity(0.9))
                                            .frame(width: 28, height: 28)
                                            .background(tint.opacity(0.1).cornerRadius(8))
                                        Text(Localization.get("Environment", lang: appLanguage))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))

                                        Spacer()

                                        NotchSegmentedPicker(
                                            options: NotchEnvironment.allCases,
                                            selection: $gemini.selectedEnvironment,
                                            titleMapper: { $0.title },
                                            tint: tint
                                        )
                                        .frame(width: 220)
                                        .disabled(!gemini.canManageConfiguration)
                                    }
                                    .padding(.top, 4)
                                    #endif
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

            AppSettingsCard(
                title: Localization.get("Floating orb window", lang: appLanguage)
            ) {
                AppSettingsRow(showDivider: false) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.1).cornerRadius(8))

                    Text(Localization.get("Show floating orb window when connected", lang: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer(minLength: 0)

                    Toggle("", isOn: $jarvisOrbBackdropEnabled)
                        .toggleStyle(NotchSwitchStyle(tint: tint))
                        .labelsHidden()
                }
            }

            AppSettingsCard(
                title: Localization.get("Push to Talk", lang: appLanguage)
            ) {
                AppSettingsRow(showDivider: false) {
                    HoldToTalkShortcutRecorderView(
                        shortcut: $holdShortcut,
                        title: Localization.get("Push to Talk key", lang: appLanguage),
                        icon: "mic",
                        helperText: nil,
                        isNotchStyle: true,
                        tint: tint
                    )
                }
            }


            AppSettingsCard(
                title: Localization.get("Context Files", lang: appLanguage)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    AppSettingsRow(showDivider: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    isUserProfileExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.text.rectangle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(tint.opacity(0.9))
                                        .frame(width: 28, height: 28)
                                        .background(tint.opacity(0.1).cornerRadius(8))
                                    Text(Localization.get("User Profile", lang: appLanguage))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Image(systemName: isUserProfileExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isUserProfileExpanded {
                                GeminiFileTextEditor(text: $userProfileDraft)
                                    .onChange(of: userProfileDraft) { _, newValue in
                                        if gemini.userProfileContent != newValue {
                                            gemini.saveUserProfile(newValue)
                                        }
                                    }
                                    .disabled(!gemini.canManageConfiguration)
                            }
                        }
                    }

                    AppSettingsRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    isMemoryExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(tint.opacity(0.9))
                                        .frame(width: 28, height: 28)
                                        .background(tint.opacity(0.1).cornerRadius(8))
                                    Text(Localization.get("Memory", lang: appLanguage))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Image(systemName: isMemoryExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isMemoryExpanded {
                                GeminiFileTextEditor(text: $memoryDraft)
                                    .onChange(of: memoryDraft) { _, newValue in
                                        if gemini.memoryContent != newValue {
                                            gemini.saveMemory(newValue)
                                        }
                                    }
                                    .disabled(!gemini.canManageConfiguration)
                            }
                        }
                    }
                }
            }

            AppSettingsCard(
                title: Localization.get("Agents", lang: appLanguage)
            ) {
                agentEditorPanel
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

            }
        }
        .onAppear(perform: syncDrafts)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in syncAgentDrafts() }
        .onChange(of: gemini.userProfileContent) { _, value in userProfileDraft = value }
        .onChange(of: gemini.memoryContent) { _, value in memoryDraft = value }
        .alert(Localization.get("Delete Agent?", lang: appLanguage), isPresented: $showingDeleteAgentAlert) {
            Button(Localization.get("Cancel", lang: appLanguage), role: .cancel) {}
            Button(Localization.get("Delete", lang: appLanguage), role: .destructive) {
                _ = gemini.deleteSelectedSystemPrompt()
                syncAgentDrafts()
            }
        } message: {
            Text(String(format: Localization.get("Delete \"%@\"?", lang: appLanguage), settingsFormattedAgentDisplayName(gemini.selectedSystemPromptPreset.title)))
        }

    }

    @ViewBuilder
    private var agentEditorPanel: some View {
        HStack(alignment: .top, spacing: 0) {
            agentListColumn
            agentDetailColumn
        }
        .frame(maxWidth: .infinity, minHeight: 480)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.24)))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .disabled(!gemini.canManageConfiguration)
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
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            gemini.selectSystemPrompt(id: prompt.id)
                            syncAgentDrafts()
                        }
                        .disabled(!gemini.canManageConfiguration)
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
                            .disabled(!gemini.canManageConfiguration)

                        HStack(spacing: 6) {
                            StandardActionButton(
                                title: Localization.get("Change Photo", lang: appLanguage),
                                icon: "photo",
                                tint: tint,
                                variant: .primary,
                                isDisabled: !gemini.canManageConfiguration
                            ) { gemini.chooseSelectedSystemPromptAvatarImage() }

                            if gemini.selectedSystemPromptAvatarImageURL != nil {
                                StandardActionButton(
                                    title: Localization.get("Clear", lang: appLanguage),
                                    icon: "xmark",
                                    tint: tint,
                                    isDisabled: !gemini.canManageConfiguration
                                ) { gemini.clearSelectedSystemPromptAvatarImage() }
                            }
                            Spacer()
                            StandardActionButton(
                                title: Localization.get("Delete Agent", lang: appLanguage),
                                icon: "trash",
                                tint: Color(nsColor: .systemRed).opacity(0.85),
                                variant: .primary,
                                isDisabled: !gemini.canManageConfiguration || !gemini.canDeleteSelectedSystemPrompt
                            ) { showingDeleteAgentAlert = true }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(spacing: 12) {
                    agentModelVoiceThinkingRow(icon: "cpu", titleKey: "Model") {
                        fixedWidthAgentMenu(title: gemini.selectedModel.displayName) {
                            if gemini.availableLiveModels.isEmpty {
                                Text(Localization.get("No local Live models found.", lang: appLanguage))
                            } else {
                                ForEach(gemini.availableLiveModels) { model in
                                    Button(model.displayName) {
                                        gemini.selectedModel = model
                                    }
                                }
                            }
                        }
                    }

                    if let message = gemini.lastLiveModelRefreshMessage, !message.isEmpty {
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Text(Localization.get(message, lang: appLanguage))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.46))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    agentModelVoiceThinkingRow(icon: "waveform", titleKey: "Voice") {
                        fixedWidthAgentMenu(title: gemini.selectedVoice.rawValue) {
                            ForEach(GeminiVoice.allCases, id: \.self) { voice in
                                Button(voice.rawValue) {
                                    gemini.selectedVoice = voice
                                }
                            }
                        }
                    }

                    agentModelVoiceThinkingRow(icon: "lightbulb", titleKey: "Thinking") {
                        fixedWidthAgentMenu(title: Localization.get(gemini.thinkingLevel.rawValue, lang: appLanguage)) {
                            ForEach(gemini.availableThinkingLevels, id: \.self) { level in
                                Button(Localization.get(level.rawValue, lang: appLanguage)) {
                                    gemini.thinkingLevel = level
                                }
                            }
                        }
                    }

                    agentModelVoiceThinkingRow(icon: "rectangle.compress.vertical", titleKey: "Media Resolution") {
                        fixedWidthAgentMenu(title: Localization.get(gemini.mediaResolution.rawValue, lang: appLanguage)) {
                            ForEach(GeminiMediaResolution.allCases, id: \.self) { resolution in
                                Button(Localization.get(resolution.rawValue, lang: appLanguage)) {
                                    gemini.mediaResolution = resolution
                                }
                            }
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            isSystemPromptExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(tint.opacity(0.9))
                                .frame(width: 28, height: 28)
                                .background(tint.opacity(0.1).cornerRadius(8))
                            Text(Localization.get("System Prompt", lang: appLanguage))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Image(systemName: isSystemPromptExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isSystemPromptExpanded {
                        GeminiFileTextEditor(text: $agentPromptDraft)
                            .onChange(of: agentPromptDraft) { _, newValue in
                                _ = gemini.saveSystemPrompt(id: currentPromptID, title: agentNameDraft, content: newValue)
                            }
                            .disabled(!gemini.canManageConfiguration)
                    }
                }

                Divider().overlay(Color.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 8) {
                    GeminiToolsPicker(selection: $gemini.enabledTools, isDisabled: !gemini.canManageConfiguration)
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

        Task {
            await gemini.refreshAvailableLiveModels(silent: true)
        }
    }

    private func syncAgentDrafts() {
        let selected = gemini.selectedSystemPromptPreset
        agentNameDraft = selected.title
        agentPromptDraft = selected.content
    }

    @ViewBuilder
    private func agentModelVoiceThinkingRow<Content: View>(
        icon: String,
        titleKey: String,
        @ViewBuilder valueMenu: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1).cornerRadius(8))
            Text(Localization.get(titleKey, lang: appLanguage))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 8)
            valueMenu()
                .labelsHidden()
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func fixedWidthAgentMenu<Items: View>(
        title: String,
        @ViewBuilder items: () -> Items
    ) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .frame(width: 150, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!gemini.canManageConfiguration)
        .opacity(gemini.canManageConfiguration ? 1 : 0.45)
    }
}

struct AgentListRow: View {
    let prompt: GeminiSystemPromptPreset
    let isSelected: Bool
    let tint: Color
    let action: () -> Void
    @AppStorage("app_language") private var appLanguage: String = "English"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GeminiAgentAvatarArtwork(
                    imageURL: prompt.resolvedAvatarImageURL,
                    symbolName: prompt.resolvedAvatarSymbolName,
                    symbolFont: .system(size: 12, weight: .semibold),
                    size: 28
                )
                Text(prompt.title.isEmpty ? Localization.get("Untitled", lang: appLanguage) : prompt.title)
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
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

