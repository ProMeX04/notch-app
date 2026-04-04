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
                        GeminiControlToggle(
                            icon: gemini.isScreenSharingEnabled ? "eye.fill" : "eye",
                            label: "Screen",
                            isActive: gemini.isScreenSharingEnabled,
                            action: { gemini.toggleScreenSharing() }
                        )
                        GeminiControlToggle(
                            icon: gemini.showTranscriptOverlay ? "text.bubble.fill" : "text.bubble",
                            label: "Subs",
                            isActive: gemini.showTranscriptOverlay,
                            action: { gemini.showTranscriptOverlay.toggle() }
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
                            // READY STATE: system prompt first, then tools, then voice/thinking
                            systemPromptSection

                            HStack(alignment: .bottom, spacing: 8) {
                                GeminiToolsPicker(selection: $gemini.enabledTools)

                                GeminiSecondaryButton(title: "Change Key") {
                                    isEditingKey = true
                                    gemini.apiKeyText = ""
                                }
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
                                            // Optional: restore the stored key
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
                                    }
                                    
                                    Spacer()
                                    
                                    Text("Setup Gemini Live")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.38))
                                    
                                    Spacer()
                                    
                                    if gemini.hasSavedAPIKey {
                                        // Invisible balance spacer
                                        Text("Back")
                                            .font(.system(size: 10, weight: .semibold))
                                            .opacity(0)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 4)

                                GeminiStyledAPIKeyField(
                                    placeholder: "Gemini API key",
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

                                if !gemini.apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    GeminiActionButton(
                                        title: gemini.isSavingAPIKey ? "Testing API Key..." : "Save API Key",
                                        icon: "checkmark.shield",
                                        tint: Color(nsColor: .systemBlue)
                                    ) {
                                        Task {
                                            if await gemini.saveAPIKey() {
                                                isEditingKey = false
                                            }
                                        }
                                    }
                                    .disabled(gemini.isSavingAPIKey || gemini.connectionState == .connecting)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                GeminiStyledAPIKeyField(placeholder: "Pexels API key", text: $gemini.pexelsAPIKeyText)
                                GeminiStyledAPIKeyField(placeholder: "Brave Search API key", text: $gemini.braveSearchAPIKeyText)

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
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
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

    private var summaryText: String {
        switch selection.count {
        case 0:
            return "None"
        case GeminiTool.allCases.count:
            return "All"
        default:
            return "\(selection.count) selected"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Tools")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(GeminiTool.allCases) { tool in
                    Button {
                        if selection.contains(tool) {
                            selection.remove(tool)
                        } else {
                            selection.insert(tool)
                        }
                    } label: {
                        if selection.contains(tool) {
                            Label(tool.displayName, systemImage: "checkmark")
                        } else {
                            Text(tool.displayName)
                        }
                    }
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
        }
        .frame(maxWidth: .infinity)
    }
}
