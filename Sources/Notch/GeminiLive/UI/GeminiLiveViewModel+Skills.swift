import AppKit
import Foundation
import NotchGeminiSkillStorage

extension GeminiLiveViewModel {
    func deleteSkill(id: String) {
        guard canManageSkills else { return }
        guard let skill = installedSkills.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Localization.get("Delete skill?")
        alert.informativeText = String(format: Localization.get("Delete \"%@\" from Notch? You can recreate it anytime."), skill.metadata.name)
        alert.addButton(withTitle: Localization.get("Delete"))
        alert.addButton(withTitle: Localization.get("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try skillsRepository.deleteSkill(id: skill.id)
            for i in systemPromptPresets.indices {
                systemPromptPresets[i].enabledSkillIDs.removeAll { $0 == skill.id }
            }
            enabledSkillIDs.remove(skill.id)
            reloadInstalledSkills()
            statusText = String(format: Localization.get("Deleted skill \"%@\"."), skill.metadata.name)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = Localization.get("Skill deletion failed.")
        }
    }

    func ingestSkillsEditorSaveFailure(_ error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func persistSkillDraftFromEditor(skillID: String?, draft: SkillDraft) throws {
        if let sid = skillID {
            _ = try skillsRepository.updateSkill(id: sid, draft: draft, allowUpdatingBuiltin: false)
        } else {
            _ = try skillsRepository.createSkill(draft: draft, source: .user)
        }
        reloadInstalledSkills()
        statusText = Localization.get("Skill saved.")
        lastErrorMessage = nil
    }

    func duplicateSkill(id: String) throws {
        _ = try skillsRepository.duplicateSkill(id: id)
        reloadInstalledSkills()
        statusText = Localization.get("Duplicated skill.")
        lastErrorMessage = nil
    }

    func duplicateSkillFromPicker(id: String) {
        do {
            try duplicateSkill(id: id)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = Localization.get("Couldn't duplicate skill.")
        }
    }

    func skillRecord(for id: String) -> SkillRecord? {
        skillsRepository.record(id: id)
    }

    func resolvedSkillDraft(forSkillID id: String) -> SkillDraft? {
        guard let record = skillsRepository.record(id: id) else { return nil }
        return SkillDraft(
            name: record.name,
            description: record.description,
            category: record.category,
            instructions: record.instructions
        )
    }

    func deleteSkill(named name: String) {
        guard let match = installedSkills.first(where: { $0.metadata.name == name }) else { return }
        deleteSkill(id: match.id)
    }

    func reloadInstalledSkills() {
        installedSkills = (try? skillsRepository.listInstalledSkillsSorted()) ?? []
        normalizeEnabledSkillIDs()
    }

    func makeSkillSessionSnapshot() -> SkillSessionSnapshot {
        let skillsById = Dictionary(uniqueKeysWithValues: activeInstalledSkills.map { ($0.id, $0) })
        let enabledIDs = activeInstalledSkills.map(\.id).sorted()
        return SkillSessionSnapshot(
            skillsById: skillsById,
            enabledSkillIDs: enabledIDs,
            effectiveTools: effectiveEnabledTools
        )
    }

    func normalizeEnabledSkillIDs() {
        guard !isNormalizingEnabledSkillIDs else { return }
        isNormalizingEnabledSkillIDs = true
        defer { isNormalizingEnabledSkillIDs = false }

        let valid = Set(installedSkills.map(\.id))
        let filtered = enabledSkillIDs.intersection(valid)
        if filtered != enabledSkillIDs {
            enabledSkillIDs = filtered
        }
    }

    func syncEnabledSkillIDsToActivePreset() {
        guard let idx = systemPromptPresets.firstIndex(where: { $0.id == selectedSystemPromptID }) else { return }
        systemPromptPresets[idx].enabledSkillIDs = enabledSkillIDs.sorted()
    }

}
