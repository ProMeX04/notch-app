import AppKit
import SwiftUI

/// Shared layout for Gemini Live panel controls (setup pickers/menus and live session bar).
private enum GeminiPanelControlMetrics {
    static let corner: CGFloat = 9
    static let hPad: CGFloat = 10
    static let vPad: CGFloat = 6
    static let minHeight: CGFloat = 30
    static let iconColWidth: CGFloat = 14
    static let labelFont = Font.system(size: 10, weight: .semibold)
    static let chevronFont = Font.system(size: 9, weight: .bold)
    /// Menu / dropdown field chrome (pre-connect)
    static let fieldFill = Color.white.opacity(0.06)
    static let fieldStroke = Color.white.opacity(0.08)
}

/// One shared row for every pre-connect `Menu` label (Prompt, Tools, Voice, Thinking, …).
private struct GeminiMenuFieldRow: View {
    enum TrailingGlyph {
        case chevron
        case ellipsis
        case none
    }

    let leadingIcon: String
    let title: String
    var trailing: TrailingGlyph = .chevron
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingIcon)
                .font(GeminiPanelControlMetrics.labelFont)
                .frame(width: GeminiPanelControlMetrics.iconColWidth, alignment: .center)
            Text(title)
                .font(GeminiPanelControlMetrics.labelFont)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Group {
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.up.chevron.down")
                        .font(GeminiPanelControlMetrics.chevronFont)
                case .ellipsis:
                    Image(systemName: "ellipsis")
                        .font(GeminiPanelControlMetrics.labelFont)
                case .none:
                    EmptyView()
                }
            }
            .foregroundStyle(isDestructive ? Color.red.opacity(0.45) : .white.opacity(0.38))
        }
        .foregroundStyle(isDestructive ? Color.red.opacity(0.88) : .white.opacity(0.78))
        .padding(.horizontal, GeminiPanelControlMetrics.hPad)
        .padding(.vertical, GeminiPanelControlMetrics.vPad)
        .frame(minHeight: GeminiPanelControlMetrics.minHeight)
        .background(
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .fill(GeminiPanelControlMetrics.fieldFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .stroke(GeminiPanelControlMetrics.fieldStroke, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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

enum GeminiPromptEditorMode: Equatable {
    case create
    case edit(String)
}

private enum GeminiSetupViewMode: Equatable {
    case home
    case agentSettings
}

struct GeminiTalkPanelView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @ObservedObject var headerAccessoryController: NotchHeaderAccessoryController
    @State private var setupViewMode: GeminiSetupViewMode = .home
    @State private var promptEditorMode: GeminiPromptEditorMode?
    @State private var promptDraftTitle = ""
    @State private var promptDraftContent = ""
    @State private var agentNameDraft = ""
    @FocusState private var isAgentNameFieldFocused: Bool

    private var statusColor: Color {
        Color(nsColor: gemini.connectionState.accentColor).ensureMinimumBrightness(factor: 0.72)
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
        if case .edit = promptEditorMode {
            return true
        }
        return false
    }

    private func beginCreatingAgent() {
        _ = gemini.createSystemPrompt()
        if gemini.hasSavedAPIKey {
            setupViewMode = .agentSettings
        } else {
            gemini.requestManageKeysPanel()
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
            gemini.requestManageKeysPanel()
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

    private func savePromptDraft() {
        let promptID: String?
        if case let .edit(id) = promptEditorMode {
            promptID = id
        } else {
            promptID = nil
        }

        guard gemini.saveSystemPrompt(id: promptID, title: promptDraftTitle, content: promptDraftContent) else {
            return
        }

        cancelPromptEditing()
    }

    private func deleteSelectedPrompt() {
        let deletedPromptID = gemini.selectedSystemPromptID
        guard gemini.deleteSelectedSystemPrompt() else { return }

        if case let .edit(id) = promptEditorMode, id == deletedPromptID {
            cancelPromptEditing()
        }
    }

    private func requestDeleteSelectedPrompt() {
        guard gemini.canDeleteSelectedSystemPrompt else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Agent?"
        alert.informativeText = "Delete \"\(gemini.selectedSystemPromptPreset.title)\"? This can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
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
        if isPromptEditorPresented {
            headerAccessoryController.leadingActions = [
                NotchHeaderAction(
                    id: "talk-back",
                    title: "Back",
                    icon: "chevron.left",
                    style: .secondary,
                    isDisabled: false,
                    action: cancelPromptEditing
                ),
                NotchHeaderAction(
                    id: "talk-save-prompt",
                    title: isEditingExistingPrompt ? "Save" : "Add",
                    icon: isEditingExistingPrompt ? "square.and.arrow.down" : "plus",
                    style: .primary,
                    isDisabled: false,
                    action: savePromptDraft
                )
            ]
            return
        }

        guard gemini.connectionState != .connected else {
            headerAccessoryController.clear()
            return
        }

        if setupViewMode == .agentSettings {
            headerAccessoryController.leadingActions = [
                NotchHeaderAction(
                    id: "talk-back",
                    title: "Back",
                    icon: "chevron.left",
                    style: .secondary,
                    isDisabled: false,
                    action: {
                        setupViewMode = .home
                    }
                )
            ]
            return
        }

        headerAccessoryController.clear()
    }

    /// No API keys are configured in the notch — use the floating panels (menu bar or prompts below).
    private var noGeminiKeySetupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gemini Live needs a Gemini API key.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text("Keys are not entered in the notch. Use the menu bar or Manage keys below.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            GeminiActionButton(
                title: "Manage keys",
                icon: "key.fill",
                tint: statusColor
            ) {
                gemini.requestManageKeysPanel()
            }
            .frame(maxWidth: .infinity)

            GeminiActionButton(
                title: gemini.connectionButtonTitle,
                icon: gemini.connectionButtonIcon,
                tint: statusColor
            ) {
                gemini.toggleConnection()
            }
            .disabled(gemini.connectionState == .connecting || !gemini.hasConfiguredAPIKey)
            .opacity(gemini.hasConfiguredAPIKey ? 1 : 0.45)
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let approval = gemini.currentPendingExecApproval {
                GeminiExecApprovalCard(
                    request: approval,
                    queueCount: gemini.pendingExecApprovals.count,
                    onApproveOnce: { gemini.approveCurrentExecApprovalOnce() },
                    onApproveExact: { gemini.approveCurrentExecApprovalExact() },
                    onApproveFamily: { gemini.approveCurrentExecApprovalFamily() },
                    onDeny: { gemini.denyCurrentExecApproval() }
                )
            }

            Group {
                if isPromptEditorPresented {
                    GeminiPromptEditorCard(
                        title: $promptDraftTitle,
                        content: $promptDraftContent,
                        isEditing: isEditingExistingPrompt
                    )
                } else if gemini.connectionState == .connected {
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.vertical, showsIndicators: false) {
                            Group {
                                if gemini.modelTranscript.isEmpty {
                                    Text("Gemini is listening...")
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

                        HStack(alignment: .center, spacing: 6) {
                            GeminiControlToggle(
                                icon: gemini.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                                label: gemini.isMicrophoneEnabled ? "Mic" : "Muted",
                                isActive: gemini.isMicrophoneEnabled,
                                action: { gemini.toggleMicrophone() }
                            )
                            GeminiScreenShareMenu(gemini: gemini)
                            GeminiControlToggle(
                                icon: gemini.showTranscriptOverlay ? "text.bubble.fill" : "text.bubble",
                                label: "Subs",
                                isActive: gemini.showTranscriptOverlay,
                                action: { gemini.showTranscriptOverlay.toggle() }
                            )
                            GeminiControlToggle(
                                icon: gemini.transcriptOverlayAutoHide ? "timer" : "pin.fill",
                                label: gemini.transcriptOverlayAutoHide ? "Hide" : "Pin",
                                isActive: gemini.transcriptOverlayAutoHide,
                                action: { gemini.transcriptOverlayAutoHide.toggle() }
                            )
                            .disabled(!gemini.showTranscriptOverlay)
                            .opacity(gemini.showTranscriptOverlay ? 1 : 0.4)
                            GeminiControlToggle(
                                icon: gemini.showLiveChatInput ? "keyboard.fill" : "keyboard",
                                label: "Type",
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
                                label: "End",
                                isActive: true,
                                isDestructive: true,
                                action: { gemini.disconnect() }
                            )
                        }
                    }
                } else {
                    // Not connected state
                    VStack(spacing: 10) {
                        if gemini.hasSavedAPIKey {
                            switch setupViewMode {
                            case .home:
                                HStack(alignment: .top, spacing: 28) {
                                    VStack(spacing: 4) {
                                        Menu {
                                            ForEach(gemini.systemPromptPresets) { prompt in
                                                Button {
                                                    gemini.selectSystemPrompt(id: prompt.id)
                                                } label: {
                                                    if prompt.id == gemini.selectedSystemPromptID {
                                                        Label(prompt.title, systemImage: "checkmark")
                                                    } else {
                                                        Text(prompt.title)
                                                    }
                                                }
                                            }
                                            Divider()
                                            Button(action: beginCreatingAgent) {
                                                Label("New Agent", systemImage: "plus")
                                            }
                                        } label: {
                                            GeminiAgentHomeAvatarFigure(
                                                statusColor: statusColor,
                                                avatarSymbolName: selectedAgentAvatarSymbolName,
                                                avatarImageURL: selectedAgentAvatarImageURL
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        Text(gemini.selectedSystemPromptPreset.title.uppercased())
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.74))
                                            .tracking(1.2)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .minimumScaleFactor(0.9)
                                            .frame(width: 128, alignment: .center)
                                    }
                                    .frame(width: 130)

                                    VStack(alignment: .leading, spacing: 12) {
                                        GeminiActionButton(
                                            title: "Settings",
                                            icon: "slider.horizontal.3",
                                            tint: statusColor
                                        ) {
                                            setupViewMode = .agentSettings
                                        }
                                        .frame(maxWidth: .infinity)

                                        GeminiActionButton(
                                            title: gemini.connectionButtonTitle,
                                            icon: gemini.connectionButtonIcon,
                                            tint: statusColor
                                        ) {
                                            gemini.toggleConnection()
                                        }
                                        .disabled(gemini.connectionState == .connecting)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .padding(.top, 20)
                                    .frame(maxWidth: 220)

                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, 12)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            case .agentSettings:
                                VStack(spacing: 12) {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            GeminiAgentSummaryCard(
                                                statusColor: statusColor,
                                                name: $agentNameDraft,
                                                avatarSymbolName: selectedAgentAvatarSymbolName,
                                                avatarImageURL: selectedAgentAvatarImageURL,
                                                nameFieldFocus: $isAgentNameFieldFocused,
                                                onSubmitName: saveAgentNameDraft,
                                                onChooseAvatar: { gemini.chooseSelectedSystemPromptAvatarImage() },
                                                onClearAvatar: { gemini.clearSelectedSystemPromptAvatarImage() }
                                            )
                                        }
                                        .frame(width: 188, alignment: .topLeading)

                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(alignment: .top, spacing: 10) {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    GeminiDropdownPicker(
                                                        label: "Voice",
                                                        leadingIcon: "waveform",
                                                        selection: $gemini.selectedVoice
                                                    )
                                                    GeminiDropdownPicker(
                                                        label: "Thinking",
                                                        leadingIcon: "brain.head.profile",
                                                        selection: $gemini.thinkingLevel
                                                    )
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                                VStack(alignment: .leading, spacing: 10) {
                                                    GeminiToolsPicker(
                                                        selection: $gemini.enabledTools,
                                                        isDisabled: !gemini.canManageSkills
                                                    )
                                                    GeminiSkillsPicker(
                                                        installedSkills: gemini.installedSkills,
                                                        selection: $gemini.enabledSkillNames,
                                                        isDisabled: !gemini.canManageSkills
                                                    )
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            }

                                            HStack(alignment: .top, spacing: 10) {
                                                GeminiSkillManagementMenu(
                                                    installedSkills: gemini.userInstalledSkills,
                                                    isDisabled: !gemini.canManageSkills,
                                                    onImport: { gemini.importSkill() },
                                                    onDelete: { gemini.deleteSkill(named: $0.metadata.name) }
                                                )
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                                GeminiEditAgentButton(onEdit: beginEditingSelectedPrompt)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }

                                            Button(role: .destructive, action: requestDeleteSelectedPrompt) {
                                                GeminiMenuFieldRow(
                                                    leadingIcon: "trash",
                                                    title: "Delete Agent",
                                                    trailing: .none,
                                                    isDestructive: true
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!gemini.canDeleteSelectedSystemPrompt)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else {
                            noGeminiKeySetupView
                        }

                        if let lastErrorMessage = gemini.lastErrorMessage {
                            Text(lastErrorMessage)
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
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .onAppear(perform: syncAgentNameDraft)
        .onAppear(perform: refreshHeaderAccessory)
        .onChange(of: gemini.selectedSystemPromptID) { _, _ in
            syncAgentNameDraft()
            refreshHeaderAccessory()
        }
        .onChange(of: isAgentNameFieldFocused) { _, isFocused in
            if !isFocused {
                saveAgentNameDraft()
            }
        }
        .onChange(of: setupViewMode) { _, _ in
            refreshHeaderAccessory()
        }
        .onChange(of: promptEditorMode) { _, _ in
            refreshHeaderAccessory()
        }
        .onChange(of: gemini.hasSavedAPIKey) { _, _ in
            refreshHeaderAccessory()
        }
        .onChange(of: gemini.connectionState) { _, _ in
            refreshHeaderAccessory()
        }
        .onChange(of: gemini.isSavingAPIKey) { _, _ in
            refreshHeaderAccessory()
        }
        .onChange(of: promptDraftContent) { _, _ in
            refreshHeaderAccessory()
        }
        .onDisappear {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(nsColor: .systemOrange).ensureMinimumBrightness(factor: 0.75))
                Text("Approve Command (\(Int(request.timeoutSeconds))s)")
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

            HStack(spacing: 10) {
                if let workingDirectory = request.workingDirectory,
                   !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("cwd: \(workingDirectory)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                GeminiExecDecisionButton(
                    title: "Deny",
                    tint: Color(nsColor: .systemRed),
                    action: onDeny
                )
                GeminiExecDecisionButton(
                    title: "Allow Once",
                    tint: Color(nsColor: .systemBlue),
                    action: onApproveOnce
                )
            }

            HStack(spacing: 8) {
                GeminiExecDecisionButton(
                    title: "Always Exact",
                    tint: Color(nsColor: .systemGreen),
                    action: onApproveExact
                )
                if let family = request.commandFamily {
                    GeminiExecDecisionButton(
                        title: "Always \(family)",
                        tint: Color(nsColor: .systemTeal),
                        action: onApproveFamily
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .systemOrange).opacity(0.35), lineWidth: 1)
        }
    }
}

struct GeminiExecDecisionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(tint.opacity(0.18))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(tint.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct GeminiPromptPicker: View {
    let prompts: [GeminiSystemPromptPreset]
    @Binding var selection: String

    private var selectedTitle: String {
        prompts.first(where: { $0.id == selection })?.title ?? prompts.first?.title ?? "Default"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Agent")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: true, vertical: false)

            Menu {
                ForEach(prompts) { prompt in
                    Button {
                        selection = prompt.id
                    } label: {
                        if prompt.id == selection {
                            Label(prompt.title, systemImage: "checkmark")
                        } else {
                            Text(prompt.title)
                        }
                    }
                }
            } label: {
                GeminiMenuFieldRow(leadingIcon: "text.quote", title: selectedTitle)
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

    private var selectedTitle: String {
        prompts.first(where: { $0.id == selection })?.title ?? prompts.first?.title ?? "Default"
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
            Text("Agent")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: true, vertical: false)

            Menu {
                ForEach(prompts) { prompt in
                    Button {
                        selection = prompt.id
                    } label: {
                        if prompt.id == selection {
                            Label(prompt.title, systemImage: "checkmark")
                        } else {
                            Text(prompt.title)
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
                        .font(GeminiPanelControlMetrics.labelFont)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(GeminiPanelControlMetrics.chevronFont)
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, GeminiPanelControlMetrics.hPad)
                .padding(.vertical, GeminiPanelControlMetrics.vPad)
                .frame(minHeight: GeminiPanelControlMetrics.minHeight)
                .background(
                    RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                        .fill(GeminiPanelControlMetrics.fieldFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                        .stroke(GeminiPanelControlMetrics.fieldStroke, lineWidth: 1)
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

    var body: some View {
        if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onChooseAvatar) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.14))

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        statusColor.opacity(0.84),
                                        Color(nsColor: .systemIndigo).opacity(0.58)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(4)

                        GeminiAgentAvatarArtwork(
                            imageURL: avatarImageURL,
                            symbolName: avatarSymbolName,
                            symbolFont: .system(size: 15, weight: .medium),
                            size: 34
                        )
                }
                .frame(width: 42, height: 42)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .focused(nameFieldFocus)
                    .onSubmit(onSubmitName)
            }

            GeminiSecondaryButton(title: "Change Photo", action: onChooseAvatar)
            GeminiSecondaryButton(title: "Clear", action: onClearAvatar)
                .disabled(avatarImageURL == nil)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct GeminiEditAgentButton: View {
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            GeminiMenuFieldRow(leadingIcon: "pencil", title: "Edit System Prompt", trailing: .none)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiPromptEditorCard: View {
    @Binding var title: String
    @Binding var content: String
    let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isEditing {
                TextField("Agent name (optional)", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                TextEditor(text: $content)
                    .font(.system(size: 11, weight: .regular))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .frame(minHeight: 72)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: GeminiPanelControlMetrics.iconColWidth, alignment: .center)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, GeminiPanelControlMetrics.vPad)
            .frame(maxWidth: .infinity, minHeight: GeminiPanelControlMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                    .fill(tint.opacity(0.2))
            )
            .overlay {
                RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shared pill chrome for live controls (`GeminiControlToggle`, screen share picker).
private struct GeminiControlPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false

    private var activeTint: Color {
        isDestructive ? Color(nsColor: .systemRed) : .white
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(GeminiPanelControlMetrics.labelFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: GeminiPanelControlMetrics.iconColWidth, alignment: .center)
            Text(label)
                .font(GeminiPanelControlMetrics.labelFont)
                .lineLimit(1)
        }
        .foregroundStyle(
            isActive
                ? activeTint.opacity(isDestructive ? 0.75 : 0.9)
                : .white.opacity(0.35)
        )
        .padding(.horizontal, GeminiPanelControlMetrics.hPad)
        .padding(.vertical, GeminiPanelControlMetrics.vPad)
        .frame(minHeight: GeminiPanelControlMetrics.minHeight)
        .background(
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .fill(isActive ? activeTint.opacity(0.12) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .stroke(isActive ? activeTint.opacity(0.25) : Color.clear, lineWidth: 0.5)
        )
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

struct GeminiScreenShareMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @State private var isPickerOpen = false

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
                screenShareRow("Share Full Screen") {
                    gemini.startFullScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow("Share Selected Region") {
                    gemini.startRegionScreenSharing()
                    isPickerOpen = false
                }
                screenShareRow("Share App Window") {
                    gemini.startWindowSharing()
                    isPickerOpen = false
                }
                if gemini.isScreenSharingEnabled {
                    Divider()
                        .padding(.vertical, 4)
                    screenShareRow("Stop Sharing", foreground: Color(nsColor: .systemRed)) {
                        gemini.stopScreenSharing()
                        isPickerOpen = false
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(minWidth: 200)
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
            return "speaker.fill"
        }
        if value < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(GeminiPanelControlMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: GeminiPanelControlMetrics.iconColWidth, alignment: .center)

            Slider(value: $value, in: 0...1)
                .controlSize(.small)
                .tint(.white.opacity(0.9))
                .frame(width: 72)
        }
        .padding(.horizontal, GeminiPanelControlMetrics.hPad)
        .padding(.vertical, GeminiPanelControlMetrics.vPad)
        .frame(minHeight: GeminiPanelControlMetrics.minHeight)
        .background(
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct GeminiSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(GeminiPanelControlMetrics.labelFont)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, GeminiPanelControlMetrics.hPad)
                .padding(.vertical, GeminiPanelControlMetrics.vPad)
                .frame(maxWidth: .infinity, minHeight: GeminiPanelControlMetrics.minHeight)
                .background(
                    RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: GeminiPanelControlMetrics.corner, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var buttonTitle: String {
        "\(label): \(selection.rawValue)"
    }

    var body: some View {
        Menu {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    if item == selection {
                        Label(item.rawValue, systemImage: "checkmark")
                    } else {
                        Text(item.rawValue)
                    }
                }
            }
        } label: {
            GeminiMenuFieldRow(leadingIcon: leadingIcon, title: buttonTitle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiToolsPicker: View {
    @Binding var selection: Set<GeminiTool>
    var lockedTools: Set<GeminiTool> = []
    var isDisabled = false

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
            return "No tools"
        case GeminiTool.coreCases.count:
            return "All tools"
        default:
            return "\(effectiveCount) tool\(effectiveCount == 1 ? "" : "s")"
        }
    }

    var body: some View {
        Menu {
            Button {
                selection = allSelectableTools
            } label: {
                if hasAllToolsSelected {
                    Label("All tools", systemImage: "checkmark")
                } else {
                    Label("All tools", systemImage: "checklist")
                }
            }

            Divider()

            ForEach(GeminiTool.coreCases) { tool in
                Button {
                    guard !lockedTools.contains(tool) else { return }
                    if selection.contains(tool) {
                        selection.remove(tool)
                    } else {
                        selection.insert(tool)
                    }
                } label: {
                    let isSelected = selection.contains(tool) || lockedTools.contains(tool)
                    if isSelected {
                        Label(tool.displayName, systemImage: lockedTools.contains(tool) ? "lock.fill" : "checkmark")
                    } else {
                        Text(tool.displayName)
                    }
                }
                .disabled(lockedTools.contains(tool))
            }
        } label: {
            GeminiMenuFieldRow(leadingIcon: "slider.horizontal.3", title: summaryText)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiSkillsPicker: View {
    let installedSkills: [InstalledSkill]
    @Binding var selection: Set<String>
    var isDisabled = false

    private var allSkillNames: Set<String> {
        Set(installedSkills.map(\.metadata.name))
    }

    private var hasAllSkillsSelected: Bool {
        !installedSkills.isEmpty && selection.isSuperset(of: allSkillNames)
    }

    private var summaryText: String {
        if selection.isEmpty {
            return "No skills"
        }
        if !installedSkills.isEmpty && selection.count == installedSkills.count {
            return "All skills"
        }
        return "\(selection.count) skill\(selection.count == 1 ? "" : "s")"
    }

    var body: some View {
        Menu {
            if installedSkills.isEmpty {
                Text("No skills installed")
            } else {
                Button {
                    selection = allSkillNames
                } label: {
                    if hasAllSkillsSelected {
                        Label("All skills", systemImage: "checkmark")
                    } else {
                        Label("All skills", systemImage: "checklist")
                    }
                }

                Divider()

                ForEach(installedSkills, id: \.metadata.name) { skill in
                    Button {
                        if selection.contains(skill.metadata.name) {
                            selection.remove(skill.metadata.name)
                        } else {
                            selection.insert(skill.metadata.name)
                        }
                    } label: {
                        if selection.contains(skill.metadata.name) {
                            Label(skill.metadata.name, systemImage: "checkmark")
                        } else {
                            Label(skill.metadata.name, systemImage: skill.metadata.icon)
                        }
                    }
                }
            }
        } label: {
            GeminiMenuFieldRow(leadingIcon: "books.vertical", title: summaryText)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeminiSkillManagementMenu: View {
    let installedSkills: [InstalledSkill]
    let isDisabled: Bool
    let onImport: () -> Void
    let onDelete: (InstalledSkill) -> Void

    var body: some View {
        Menu {
            Button(action: onImport) {
                Label("Add Skill", systemImage: "plus")
            }

            Divider()

            if installedSkills.isEmpty {
                Text("No user skills")
            } else {
                ForEach(installedSkills, id: \.metadata.name) { skill in
                    Button(role: .destructive) {
                        onDelete(skill)
                    } label: {
                        Label("Delete \(skill.metadata.name)", systemImage: "trash")
                    }
                }
            }
        } label: {
            GeminiMenuFieldRow(leadingIcon: "square.and.arrow.down", title: "Manage skills", trailing: .ellipsis)
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
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 128, height: 128)
                .scaleEffect(isPulsing ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isPulsing)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            statusColor.opacity(0.8),
                            Color(nsColor: .systemIndigo).opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 104)
                .shadow(color: statusColor.opacity(0.4), radius: 12)

            GeminiAgentAvatarArtwork(
                imageURL: avatarImageURL,
                symbolName: avatarSymbolName,
                symbolFont: .system(size: 38, weight: .medium),
                size: 104
            )
        }
        .offset(y: -8)
        .frame(width: 138, height: 132, alignment: .top)
        .onAppear {
            isPulsing = true
        }
    }
}
