import Foundation

public enum SkillDraftValidator {
    public static let nameMaxLength = 120
    public static let descriptionMaxLength = 500
    public static let instructionsMaxLength = 50_000
    public static let categoryMaxLength = 64

    /// Validate user-facing skill draft (create/edit + tool path before approval).
    public static func validate(
        draft: SkillDraft,
        existingRecords: [SkillRecord],
        excludingRecordID: String?,
        requireNonEmptyInstructions: Bool = true
    ) -> Result<Void, SkillDraftValidationError> {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = draft.instructions

        guard !name.isEmpty else { return .failure(.emptyName) }
        guard name.count <= nameMaxLength else { return .failure(.nameTooLong) }
        guard !containsForbiddenNameCharacters(name) else { return .failure(.invalidNameCharacters) }

        guard description.count <= descriptionMaxLength else { return .failure(.descriptionTooLong) }
        guard category.count <= categoryMaxLength else { return .failure(.categoryTooLong) }

        if requireNonEmptyInstructions {
            guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.emptyInstructions)
            }
        }
        guard instructions.count <= instructionsMaxLength else { return .failure(.instructionsTooLarge) }

        let activeOthers = existingRecords.filter { !$0.isArchived && $0.id != excludingRecordID }
        let clash = activeOthers.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
        if clash { return .failure(.duplicateName) }

        return .success(())
    }

    private static func containsForbiddenNameCharacters(_ name: String) -> Bool {
        if name.rangeOfCharacter(from: .controlCharacters) != nil {
            return true
        }
        return name.unicodeScalars.contains(where: { $0.value == 0xFFFE || $0.value == 0xFFFF })
    }
}

public enum SkillDraftValidationError: Equatable, Sendable, LocalizedError {
    case emptyName
    case nameTooLong
    case invalidNameCharacters
    case descriptionTooLong
    case categoryTooLong
    case emptyInstructions
    case instructionsTooLarge
    case duplicateName

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Skill name is required."
        case .nameTooLong: return "Skill name is too long."
        case .invalidNameCharacters: return "Skill name contains unsupported control characters."
        case .descriptionTooLong: return "Description is too long."
        case .categoryTooLong: return "Category is too long."
        case .emptyInstructions: return "Instructions must not be empty."
        case .instructionsTooLarge: return "Instructions exceed the maximum allowed size."
        case .duplicateName: return "A skill with this name already exists."
        }
    }
}

extension SkillRecord {
    public static func gettingStartedSeed(now: Date = Date()) -> SkillRecord {
        let body = """
        You are helping someone use Notch on macOS. Keep answers short, practical, and action-oriented.

        What Notch is
        - Notch sits in the Mac menu bar and notch area: quick access to Gemini Live “Talk”, focus tools, and integrations that use on-device permissions when the user enables them.

        First-time setup
        - Open Notch settings and pick a connection mode: personal API key or a managed server URL the user trusts.
        - If using an API key: paste it once in settings; it is stored in the user’s Notch state folder.
        - Pick a voice/model for the active agent preset.

        Tools and privacy
        - Tools (read files, calendar, browser control, etc.) are **off unless the user explicitly enables them per agent preset** in Talk settings.
        - Mention that sensitive actions (like running shell commands) may require explicit user approval inside Notch before they run.
        - macOS permissions (Screen Recording, Accessibility, Microphone, Calendar, Automation) are enforced by the system; ask the user to grant them in System Settings if a feature fails.

        Skills
        - “Skills” add optional playbooks the model can read via the `read` tool when relevant. Users can edit skills in Settings; built-in seeds can be duplicated.

        Troubleshooting cues
        - If audio fails: verify microphone permission and that Talk is actually connected (not paused on an error badge).
        - If automations mis-click: Accessibility permission may be missing for Notch.

        Stay factual: describe UI labels as “may vary by version”; don’t invent hidden toggles or promise network access without the user configuring it.
        """
        return SkillRecord(
            id: SkillRecord.gettingStartedBuiltinID,
            name: "Getting Started",
            description: "Onboarding playbook for configuring Notch, tools, permissions, and skills.",
            category: "builtin",
            instructions: body,
            createdAt: now,
            updatedAt: now,
            source: .builtin,
            isArchived: false
        )
    }
}
