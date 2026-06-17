import AppKit
import Foundation

@MainActor
extension GeminiLiveViewModel {
    func configureSkillWriterCallbacks() {
        let repo = toolingController.skillsRepository
        session.skillDraftValidationRecordsProvider = {
            repo.allRecords()
        }
        session.onSkillWriterApprovalRequested = { [weak self] request in
            DispatchQueue.main.async {
                self?.presentSkillWriterApprovalAlert(for: request)
            }
        }
        session.onSkillWriterExecuteApproved = { [weak self] pending, reply in
            Task { @MainActor [weak self] in
                guard let self else {
                    reply(["success": false, "error": "Skill writer handler unavailable."])
                    return
                }
                reply(self.persistSkillDraftAfterToolApproval(pending))
            }
        }
    }

    private func persistSkillDraftAfterToolApproval(_ pending: PendingSkillWriterCall) -> [String: Any] {
        do {
            let record = try skillsRepository.applyToolWrite(action: pending.action, draft: pending.draft, skillId: pending.existingSkillID)
            reloadInstalledSkills()
            return [
                "success": true,
                "skillId": record.id,
                "name": record.name,
                "message": "Skill saved to Notch Settings.",
            ]
        } catch {
            return ["success": false, "error": (error as? LocalizedError)?.errorDescription ?? error.localizedDescription]
        }
    }

    private func presentSkillWriterApprovalAlert(for request: SkillWriterApprovalRequest) {
        NSApp.activate(ignoringOtherApps: true)
        postToolAction(
            label: Localization.get("Skill write approval needed"),
            icon: "wand.and.rays.inverse",
            showsInOverlay: false,
            autoClearAfter: nil
        )
        onExecApprovalAttentionRequested?()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = request.summary
        alert.informativeText = request.preview
        alert.addButton(withTitle: Localization.get("Allow Save"))
        alert.addButton(withTitle: Localization.get("Deny"))
        if alert.runModal() == .alertFirstButtonReturn {
            session.approveSkillWriterCall(toolCallID: request.toolCallID)
        } else {
            session.denySkillWriterCall(toolCallID: request.toolCallID)
        }
    }
}
