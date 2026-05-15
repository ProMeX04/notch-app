import AppKit
import Foundation
import NotchGeminiSkillStorage

extension GeminiLiveViewModel {
    var selectedSystemPromptPreset: GeminiSystemPromptPreset {
        systemPromptPresets.first(where: { $0.id == selectedSystemPromptID })
            ?? systemPromptPresets.first
            ?? GeminiSystemPromptPreset.defaultPreset
    }

    var activeInstalledSkills: [InstalledSkill] {
        let lookup = Dictionary(uniqueKeysWithValues: installedSkills.map { ($0.id, $0) })
        return enabledSkillIDs.sorted().compactMap { lookup[$0] }
    }

    var userInstalledSkills: [InstalledSkill] {
        installedSkills.filter { $0.source != .builtin }
    }

    var effectiveEnabledTools: Set<GeminiTool> {
        enabledTools
    }

    var canManageSkills: Bool {
        canManageConfiguration
    }

    var selectedSystemPromptTitle: String {
        selectedSystemPromptPreset.title
    }

    var selectedSystemPromptAvatarSymbolName: String {
        selectedSystemPromptPreset.resolvedAvatarSymbolName
    }

    var selectedSystemPromptAvatarImageURL: URL? {
        agentAvatarStore.imageURL(for: selectedSystemPromptPreset.avatarImageFilename)
    }

    var canDeleteSelectedSystemPrompt: Bool {
        systemPromptPresets.count > 1
    }

    func selectSystemPrompt(id: String) {
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) else { return }
        guard selectedSystemPromptID != id else { return }
        selectedSystemPromptID = id
        systemPromptPresets[existingIndex].lastUsedAt = Date()
        applySelectedPresetRuntimeState()
        persistSettings()
    }

    @discardableResult
    func createSystemPrompt() -> GeminiSystemPromptPreset {
        let preset = GeminiSystemPromptPreset(
            id: UUID().uuidString,
            title: nextDefaultAgentTitle(),
            content: "",
            enabledTools: [],
            voice: GeminiVoice.kore.rawValue,
            model: GeminiLiveModel.flashLivePreview.rawValue,
            thinkingLevel: GeminiThinkingLevel.off.rawValue,
            lastUsedAt: Date()
        )
        systemPromptPresets.append(preset)
        selectedSystemPromptID = preset.id
        applySelectedPresetRuntimeState()
        persistSettings()
        return preset
    }

    func renameSelectedSystemPrompt(to title: String) {
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? systemPromptPresets[existingIndex].title : trimmedTitle
        guard systemPromptPresets[existingIndex].title != resolvedTitle else { return }
        systemPromptPresets[existingIndex].title = resolvedTitle
        persistSettings()
    }

    func chooseSelectedSystemPromptAvatarImage() {
        guard canManageSkills else { return }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        panel.message = "Choose an image for this agent avatar."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let filename = try agentAvatarStore.saveImage(from: url, presetID: selectedSystemPromptID)
            systemPromptPresets[existingIndex].avatarImageFilename = filename
            persistSettings()
            statusText = "Agent avatar updated."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Avatar update failed."
        }
    }

    func clearSelectedSystemPromptAvatarImage() {
        guard canManageSkills else { return }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        let existingFilename = systemPromptPresets[existingIndex].avatarImageFilename
        guard existingFilename != nil else { return }
        agentAvatarStore.deleteImage(named: existingFilename)
        systemPromptPresets[existingIndex].avatarImageFilename = nil
        persistSettings()
        statusText = "Agent avatar removed."
        lastErrorMessage = nil
    }

    @discardableResult
    func saveSystemPrompt(id: String?, title: String, content: String) -> Bool {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id, let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) {
            let resolvedTitle = trimmedTitle.isEmpty ? systemPromptPresets[existingIndex].title : trimmedTitle
            systemPromptPresets[existingIndex].title = resolvedTitle
            systemPromptPresets[existingIndex].content = trimmedContent
            systemPromptPresets[existingIndex].lastUsedAt = Date()
            selectedSystemPromptID = id
        } else {
            let resolvedTitle = trimmedTitle.isEmpty ? "Agent \(systemPromptPresets.count + 1)" : trimmedTitle
            let preset = GeminiSystemPromptPreset(
                id: UUID().uuidString,
                title: resolvedTitle,
                content: trimmedContent,
                enabledTools: [],
                voice: GeminiVoice.kore.rawValue,
                model: GeminiLiveModel.flashLivePreview.rawValue,
                thinkingLevel: GeminiThinkingLevel.off.rawValue,
                lastUsedAt: Date()
            )
            systemPromptPresets.append(preset)
            selectedSystemPromptID = preset.id
        }

        normalizeSystemPromptSelection()
        persistSettings()
        return true
    }

    private func nextDefaultAgentTitle() -> String {
        let prefix = "Agent "
        let maxIndex = systemPromptPresets.compactMap { preset -> Int? in
            guard preset.title.hasPrefix(prefix) else { return nil }
            let suffix = preset.title.dropFirst(prefix.count)
            return Int(suffix)
        }
        .max() ?? 0

        return "Agent \(maxIndex + 1)"
    }

    @discardableResult
    func deleteSystemPrompt(id: String) -> Bool {
        guard systemPromptPresets.count > 1 else { return false }
        guard let existingIndex = systemPromptPresets.firstIndex(where: { $0.id == id }) else { return false }

        agentAvatarStore.deleteImage(named: systemPromptPresets[existingIndex].avatarImageFilename)
        systemPromptPresets.remove(at: existingIndex)
        normalizeSystemPromptSelection()
        persistSettings()
        return true
    }

    @discardableResult
    func deleteSelectedSystemPrompt() -> Bool {
        deleteSystemPrompt(id: selectedSystemPromptID)
    }

    func normalizeSystemPromptSelection() {
        if systemPromptPresets.isEmpty {
            systemPromptPresets = GeminiSystemPromptPreset.defaultPresets
        }

        if !systemPromptPresets.contains(where: { $0.id == selectedSystemPromptID }) {
            selectedSystemPromptID = systemPromptPresets.first?.id ?? GeminiSystemPromptPreset.defaultPreset.id
        }

        applySelectedPresetRuntimeState()
    }

    func applySelectedPresetRuntimeState() {
        let active = selectedSystemPromptPreset
        thinkingLevel = active.thinkingEnum
        selectedVoice = active.voiceEnum
        selectedModel = active.modelEnum
        enabledTools = active.toolSet
        enabledSkillIDs = Set(active.enabledSkillIDs)
        normalizeEnabledSkillIDs()
        syncEnabledSkillIDsToActivePreset()
    }

    func buildSystemPrompt(
        activeSkills: [InstalledSkill],
        effectiveTools: Set<GeminiTool>,
        userContent: String,
        memoryContent: String
    ) -> String {
        let promptBody = selectedSystemPromptPreset.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPromptBody = promptBody
        let skillPrompt = SkillPromptComposer.buildPromptSection(
            for: activeSkills,
            canReadSkills: effectiveTools.contains(.read) || effectiveTools.contains(.exec)
        )
        let userPrompt = buildInjectedPromptSection(
            title: "User profile",
            tag: "user",
            content: userContent
        )
        let memoryPrompt = buildInjectedPromptSection(
            title: "Memory",
            tag: "memory",
            content: memoryContent
        )
        let optionalSkillSection = skillPrompt.isEmpty ? "" : "\n\n\(skillPrompt)"
        let optionalUserSection = userPrompt.isEmpty ? "" : "\n\n\(userPrompt)"
        let optionalMemorySection = memoryPrompt.isEmpty ? "" : "\n\n\(memoryPrompt)"
        let toolRules = buildToolRules(for: effectiveTools)
        let optionalToolRulesSection = toolRules.isEmpty ? "" : "\n\nTool rules:\n\(toolRules)"

        return """
        \(resolvedPromptBody)
        \(optionalToolRulesSection)
        \(optionalUserSection)
        \(optionalMemorySection)
        \(optionalSkillSection)
        """
    }

    func saveUserProfile(_ content: String) {
        do {
            try userStore.saveUserProfile(content)
            userProfileContent = content
        } catch {
            lastErrorMessage = "Failed to save user profile."
        }
    }

    func saveMemory(_ content: String) {
        do {
            try memoryStore.saveMemory(content)
            memoryContent = content
        } catch {
            lastErrorMessage = "Failed to save memory."
        }
    }

    private func buildInjectedPromptSection(title: String, tag: String, content: String) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        return """
        \(title):
        <\(tag)>
        \(trimmedContent)
        </\(tag)>
        """
    }

    private func buildToolRules(for effectiveTools: Set<GeminiTool>) -> String {
        var lines: [String] = []

        if effectiveTools.contains(.webSearch) {
            lines.append("- When the user asks for up-to-date information, use the built-in Google Search tool instead of guessing.")
        }
        if effectiveTools.contains(.read) {
            lines.append("- Use `read` to examine files. It supports text files and common images.")
        }
        if effectiveTools.contains(.appleMail) {
            lines.append("- Use `appleMail` to search or list recent emails from Apple Mail, or read full email bodies when available; it may fall back to summary/snippet content.")
        }
        if effectiveTools.contains(.appControl) {
            lines.append("- Use `appControl` to open, quit, or check macOS apps. Use exact app names. Do not use for opening URLs.")
        }
        if effectiveTools.contains(.mediaControl) {
            lines.append("- Use `mediaControl` for playback (play, pause, next, previous) and system volume. If no media app is running, say so.")
        }
        if effectiveTools.contains(.pomodoro) {
            lines.append("- Use `pomodoro` to control the Notch Pomodoro timer: start, pause, resume, reset, set durations, check status. If the user says stop/end/cancel focus, call reset.")
        }
        if effectiveTools.contains(.browserControl) {
            lines.append("- Use `browserControl` to open URLs, play music via DuckDuckGo Lucky, or read the current browser tab content.")
        }
        if effectiveTools.contains(.localFileSearch) {
            lines.append("- Use `localFileSearch` to search indexed local files, folders, apps, and media.")
        }
        if effectiveTools.contains(.memory) {
            lines.append("- Use `memory` to read or write persistent USER.md (identity, preferences) and MEMORY.md (durable facts, habits). Use write-user for profile updates and write-memory for broader long-term notes.")
        }
        if effectiveTools.contains(.exec) {
            lines.append("- Use `exec` to run shell commands. Every command requires explicit user approval before execution. Prefer native tools over exec when possible.")
        }
        if effectiveTools.contains(.skillWriter) {
            lines.append("- Use `skillWriter` only to persist reusable skills the user confirms. Saves require explicit approval in Notch; never claim a skill saved until the approval flow succeeds.")
        }

        return lines.joined(separator: "\n")
    }
}
