import SwiftUI
enum GeminiPromptEditorMode: Equatable {
    case create
    case edit(String)
}

struct GeminiTalkPanelView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @State private var isEditingKey = false
    @State private var promptEditorMode: GeminiPromptEditorMode?
    @State private var promptDraftTitle = ""
    @State private var promptDraftContent = ""

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

    @ViewBuilder
    private var systemPromptSection: some View {
        HStack(alignment: .bottom, spacing: 8) {
            GeminiPromptPicker(
                prompts: gemini.systemPromptPresets,
                selection: selectedPromptBinding
            )

            GeminiPromptManagementMenu(
                canDelete: gemini.canDeleteSelectedSystemPrompt,
                onCreate: beginCreatingPrompt,
                onEdit: beginEditingSelectedPrompt,
                onDelete: deleteSelectedPrompt
            )
        }
    }

    private var isEditingExistingPrompt: Bool {
        if case .edit = promptEditorMode {
            return true
        }
        return false
    }

    private func beginCreatingPrompt() {
        promptEditorMode = .create
        promptDraftTitle = ""
        promptDraftContent = ""
    }

    private func beginEditingSelectedPrompt() {
        let selectedPrompt = gemini.selectedSystemPromptPreset
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
                    ScrollView(.vertical, showsIndicators: false) {
                        GeminiPromptEditorCard(
                            title: $promptDraftTitle,
                            content: $promptDraftContent,
                            isEditing: isEditingExistingPrompt,
                            onSave: savePromptDraft,
                            onCancel: cancelPromptEditing
                        )
                    }
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

                        HStack(spacing: 6) {
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
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                        if gemini.hasSavedAPIKey && !isEditingKey {
                            HStack(alignment: .bottom, spacing: 8) {
                                GeminiPromptPicker(
                                    prompts: gemini.systemPromptPresets,
                                    selection: selectedPromptBinding
                                )
                                GeminiPromptManagementMenu(
                                    canDelete: gemini.canDeleteSelectedSystemPrompt,
                                    onCreate: beginCreatingPrompt,
                                    onEdit: beginEditingSelectedPrompt,
                                    onDelete: deleteSelectedPrompt
                                )
                                GeminiSecondaryButton(title: "Change Key") {
                                    gemini.clearKeyDrafts()
                                    isEditingKey = true
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(alignment: .bottom, spacing: 8) {
                                GeminiToolsPicker(
                                    selection: $gemini.enabledTools,
                                    isDisabled: !gemini.canManageSkills
                                )
                                GeminiSkillsPicker(
                                    installedSkills: gemini.installedSkills,
                                    selection: $gemini.enabledSkillNames,
                                    isDisabled: !gemini.canManageSkills
                                )
                                GeminiSkillManagementMenu(
                                    installedSkills: gemini.userInstalledSkills,
                                    isDisabled: !gemini.canManageSkills,
                                    onImport: { gemini.importSkill() },
                                    onDelete: { gemini.deleteSkill(named: $0.metadata.name) }
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(alignment: .bottom, spacing: 8) {
                                GeminiDropdownPicker(
                                    label: "Voice",
                                    selection: $gemini.selectedVoice
                                )
                                GeminiDropdownPicker(
                                    label: "Thinking",
                                    selection: $gemini.thinkingLevel
                                )
                                GeminiActionButton(
                                    title: gemini.connectionButtonTitle,
                                    icon: gemini.connectionButtonIcon,
                                    tint: statusColor
                                ) {
                                    gemini.toggleConnection()
                                }
                                .disabled(gemini.connectionState == .connecting)
                            }

                        } else {
                            // SETUP STATE: Missing key or changing key
                            VStack(spacing: 12) {
                                HStack {
                                    if gemini.hasSavedAPIKey {
                                        Button(action: {
                                            isEditingKey = false
                                            gemini.clearKeyDrafts()
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "chevron.left")
                                                    .font(.system(size: 10, weight: .bold))
                                                Text("Back")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .foregroundStyle(.white.opacity(0.4))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.white.opacity(0.04))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text("Back")
                                            .font(.system(size: 10, weight: .semibold))
                                            .opacity(0)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("Setup Gemini Live")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.38))
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        Task {
                                            if await gemini.saveServiceKeys() {
                                                isEditingKey = false
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.and.arrow.down")
                                                .font(.system(size: 10, weight: .bold))
                                            Text("Save")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .foregroundStyle(
                                            (gemini.isSavingAPIKey || gemini.isSavingServiceKeys || gemini.connectionState == .connecting)
                                                ? .white.opacity(0.2)
                                                : Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.72)
                                        )
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.04))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(gemini.isSavingAPIKey || gemini.isSavingServiceKeys || gemini.connectionState == .connecting)
                                }
                                .padding(.top, 4)

                                GeminiStyledAPIKeyField(
                                    placeholder: "Gemini API key (leave blank to keep current)",
                                    text: $gemini.apiKeyText,
                                    onCommit: {
                                        guard !gemini.apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                        Task {
                                            if await gemini.saveAPIKey() {
                                                isEditingKey = false
                                            }
                                        }
                                    }
                                )

                                GeminiStyledAPIKeyField(
                                    placeholder: "Pexels API key (leave blank to keep current)",
                                    text: $gemini.pexelsAPIKeyText
                                )
                                GeminiStyledAPIKeyField(
                                    placeholder: "Brave Search API key (leave blank to keep current)",
                                    text: $gemini.braveSearchAPIKeyText
                                )

                                if !gemini.hasSavedAPIKey {
                                    systemPromptSection
                                }
                            }
                            .padding(.horizontal, 2)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: gemini.apiKeyText.isEmpty)
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
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
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
            Text("System Prompt")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

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
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10, weight: .semibold))
                    Text(selectedTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeminiPromptManagementMenu: View {
    let canDelete: Bool
    let onCreate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("Manage")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(action: onCreate) {
                    Label("New Prompt", systemImage: "plus")
                }

                Button(action: onEdit) {
                    Label("Edit Selected", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(!canDelete)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Actions")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 112)
    }
}

struct GeminiPromptEditorCard: View {
    @Binding var title: String
    @Binding var content: String
    let isEditing: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var isSaveDisabled: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Back")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(isEditing ? "Edit Prompt" : "New Prompt")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))

                Spacer()

                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "square.and.arrow.down" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(isEditing ? "Save" : "Add")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isSaveDisabled ? .white.opacity(0.2) : Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .disabled(isSaveDisabled)
            }
            .padding(.top, 4)

            TextField("Prompt name", text: $title)
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
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.2))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GeminiControlToggle: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDestructive: Bool = false
    let action: () -> Void

    private var activeTint: Color {
        isDestructive ? Color(nsColor: .systemRed) : .white
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(
                isActive
                    ? activeTint.opacity(isDestructive ? 0.75 : 0.9)
                    : .white.opacity(0.35)
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? activeTint.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? activeTint.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GeminiScreenShareMenu: View {
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        Menu {
            Button("Share Full Screen") {
                gemini.startFullScreenSharing()
            }
            Button("Share Selected Region") {
                gemini.startRegionScreenSharing()
            }
            Button("Share App Window") {
                gemini.startWindowSharing()
            }
            if gemini.isScreenSharingEnabled {
                Divider()
                Button("Stop Sharing") {
                    gemini.stopScreenSharing()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: gemini.screenSharingIcon)
                    .font(.system(size: 10, weight: .semibold))
                Text(gemini.screenSharingLabel)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(
                gemini.isScreenSharingEnabled
                    ? Color.white.opacity(0.9)
                    : Color.white.opacity(0.35)
            )
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(gemini.isScreenSharingEnabled ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(gemini.isScreenSharingEnabled ? Color.white.opacity(0.25) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Ô nhập key: placeholder + viền, nền, font monospaced.
struct GeminiStyledAPIKeyField: View {
    let placeholder: String
    @Binding var text: String
    var onCommit: (() -> Void)?

    init(placeholder: String, text: Binding<String>, onCommit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onCommit = onCommit
    }

    var body: some View {
        TextField(placeholder, text: $text, onCommit: { onCommit?() })
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
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
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 12)

            Slider(value: $value, in: 0...1)
                .tint(.white.opacity(0.9))
                .frame(width: 78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct GeminiSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
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
    @Binding var selection: T

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(label, selection: $selection) {
                ForEach(Array(T.allCases), id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeminiToolsPicker: View {
    @Binding var selection: Set<GeminiTool>
    var lockedTools: Set<GeminiTool> = []
    var isDisabled = false

    private var summaryText: String {
        let effectiveCount = selection.union(lockedTools).count
        switch effectiveCount {
        case 0:
            return "None"
        case GeminiTool.coreCases.count:
            return "All"
        default:
            return "\(effectiveCount) selected"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Tools")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
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
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                    Text(summaryText)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeminiSkillsPicker: View {
    let installedSkills: [InstalledSkill]
    @Binding var selection: Set<String>
    var isDisabled = false

    private var summaryText: String {
        if selection.isEmpty {
            return "None"
        }
        if !installedSkills.isEmpty && selection.count == installedSkills.count {
            return "All"
        }
        return "\(selection.count) selected"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Skills")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                if installedSkills.isEmpty {
                    Text("No skills installed")
                } else {
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
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 10, weight: .semibold))
                    Text(summaryText)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GeminiSkillManagementMenu: View {
    let installedSkills: [InstalledSkill]
    let isDisabled: Bool
    let onImport: () -> Void
    let onDelete: (InstalledSkill) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("Skills")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

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
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Manage Skills")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
        .frame(width: 140)
    }
}
