import Foundation
import NotchGeminiSkillStorage

@main
enum NotchSkillsTestsRunner {
    static func main() {
        var failures = 0

        func check(_ ok: Bool, _ message: String) {
            guard !ok else { return }
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }

        func checkEqual<A: Equatable>(_ lhs: A, _ rhs: A, _ message: String) {
            check(lhs == rhs, message)
        }

        // MARK: SkillRecord.gettingStartedSeed

        let seeded = SkillRecord.gettingStartedSeed()
        checkEqual(seeded.id, SkillRecord.gettingStartedBuiltinID, "getting started id stable")
        checkEqual(seeded.name, "Getting Started", "getting started name")
        checkEqual(seeded.source, .builtin, "getting started source is builtin")
        check(!seeded.instructions.isEmpty, "getting started instructions non-empty")

        // MARK: SkillDraftValidator - name validation

        // Empty name rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "", description: "d", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "empty name rejected"
        )

        // Whitespace-only name rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "   ", description: "d", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "whitespace-only name rejected"
        )

        // Name too long rejected
        let longName = String(repeating: "a", count: SkillDraftValidator.nameMaxLength + 1)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: longName, description: "d", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "name too long rejected"
        )

        // Name at max length accepted
        let maxName = String(repeating: "a", count: SkillDraftValidator.nameMaxLength)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: maxName, description: "d", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isSuccess,
            "name at max length accepted"
        )

        // Control characters in name rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "Test\u{0000}Name", description: "d", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "control char in name rejected"
        )

        // Valid plain name accepted
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "My Skill", description: "desc", category: "cat", instructions: "inst"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isSuccess,
            "valid plain name accepted"
        )

        // MARK: SkillDraftValidator - description validation

        // Description too long rejected
        let longDesc = String(repeating: "x", count: SkillDraftValidator.descriptionMaxLength + 1)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: longDesc, category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "description too long rejected"
        )

        // Empty description accepted (when requireNonEmptyInstructions is false and description not checked)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "", category: "c", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: false
            ).isSuccess,
            "empty description with non-empty instructions accepted"
        )

        // MARK: SkillDraftValidator - category validation

        // Category too long rejected
        let longCat = String(repeating: "x", count: SkillDraftValidator.categoryMaxLength + 1)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: longCat, instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "category too long rejected"
        )

        // Whitespace category is trimmed (should pass length check)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "   ", instructions: "i"),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isSuccess,
            "whitespace category trimmed and accepted (length ok)"
        )

        // MARK: SkillDraftValidator - instructions validation

        // Empty instructions rejected when required
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "c", instructions: ""),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "empty instructions rejected when required"
        )

        // Whitespace-only instructions rejected when required
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "c", instructions: "   \n\t  "),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "whitespace-only instructions rejected when required"
        )

        // Empty instructions accepted when not required
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "c", instructions: ""),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: false
            ).isSuccess,
            "empty instructions accepted when not required"
        )

        // Instructions too large rejected
        let largeInstructions = String(repeating: "x", count: SkillDraftValidator.instructionsMaxLength + 1)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "c", instructions: largeInstructions),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isFailure,
            "instructions too large rejected"
        )

        // Instructions at max length accepted
        let maxInstructions = String(repeating: "x", count: SkillDraftValidator.instructionsMaxLength)
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "n", description: "d", category: "c", instructions: maxInstructions),
                existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
            ).isSuccess,
            "instructions at max length accepted"
        )

        // MARK: SkillDraftValidator - duplicate name

        let existingRecords = [
            SkillRecord(
                id: "existing-1",
                name: "My Skill",
                description: "desc",
                category: "cat",
                instructions: "inst",
                createdAt: Date(), updatedAt: Date(),
                source: .user,
                isArchived: false
            )
        ]

        // Duplicate name rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "My Skill", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isFailure,
            "duplicate name rejected"
        )

        // Duplicate name case-insensitive rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "my skill", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isFailure,
            "duplicate name case-insensitive rejected"
        )

        // Duplicate name with different case (upper) rejected
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "MY SKILL", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isFailure,
            "duplicate name uppercase rejected"
        )

        // Same name but excluding self is accepted
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "My Skill", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: "existing-1",
                requireNonEmptyInstructions: true
            ).isSuccess,
            "same name excluding self accepted"
        )

        // Archived record with same name is accepted
        let archivedRecords = [
            SkillRecord(
                id: "archived-1",
                name: "My Skill",
                description: "desc",
                category: "cat",
                instructions: "inst",
                createdAt: Date(), updatedAt: Date(),
                source: .user,
                isArchived: true
            )
        ]
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "My Skill", description: "d", category: "c", instructions: "i"),
                existingRecords: archivedRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isSuccess,
            "archived record with same name is ignored (accepted)"
        )

        // Different name is accepted
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "Different Skill", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isSuccess,
            "different name accepted"
        )

        // Name with extra whitespace is trimmed and matches
        check(
            SkillDraftValidator.validate(
                draft: SkillDraft(name: "  My Skill  ", description: "d", category: "c", instructions: "i"),
                existingRecords: existingRecords,
                excludingRecordID: nil,
                requireNonEmptyInstructions: true
            ).isFailure,
            "trimmed name matches existing (rejected)"
        )

        // MARK: SkillDraftValidationError cases

        switch SkillDraftValidator.validate(
            draft: SkillDraft(name: "", description: "d", category: "c", instructions: "x"),
            existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
        ) {
        case .success:
            check(false, "empty name should fail")
        case let .failure(err):
            checkEqual(err, .emptyName, "error is emptyName")
        }

        switch SkillDraftValidator.validate(
            draft: SkillDraft(name: "x", description: "", category: "", instructions: "x"),
            existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
        ) {
        case .success:
            break
        case let .failure(err):
            check(false, "name-only validation should pass: \(err)")
        }

        switch SkillDraftValidator.validate(
            draft: SkillDraft(name: "Big", description: "", category: "c", instructions: String(repeating: "z", count: SkillDraftValidator.instructionsMaxLength + 1)),
            existingRecords: [], excludingRecordID: nil, requireNonEmptyInstructions: true
        ) {
        case .success:
            check(false, "instructions should exceed limit")
        case let .failure(err):
            checkEqual(err, .instructionsTooLarge, "instructions size rejection")
        }

        // MARK: SkillV2Persistence

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notch-skills-tests-\(UUID().uuidString).json", isDirectory: false)

        let persistence = SkillV2Persistence(fileURL: tmp)
        do {
            try persistence.loadIfPresent()
            try persistence.upsert(seeded)
            try persistence.saveToDisk()

            let roundTrip = SkillV2Persistence(fileURL: tmp)
            try roundTrip.loadIfPresent()
            checkEqual(roundTrip.snapshot().count, 1, "json round-trip count matches")
            checkEqual(roundTrip.skill(id: seeded.id)?.name, seeded.name, "json restores name field")
        } catch {
            check(false, "persistence error \(error)")
        }

        // MARK: SkillV2Models Codable round-trip

        let record = SkillRecord(
            id: "test-id",
            name: "Test Skill",
            description: "A test skill",
            category: "testing",
            instructions: "Do the thing",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 100),
            source: .user,
            isArchived: false
        )

        do {
            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(SkillRecord.self, from: data)
            checkEqual(decoded.id, record.id, "id round-trip")
            checkEqual(decoded.name, record.name, "name round-trip")
            checkEqual(decoded.description, record.description, "description round-trip")
            checkEqual(decoded.category, record.category, "category round-trip")
            checkEqual(decoded.instructions, record.instructions, "instructions round-trip")
            checkEqual(decoded.source, record.source, "source round-trip")
            checkEqual(decoded.isArchived, record.isArchived, "isArchived round-trip")
        } catch {
            check(false, "SkillRecord codable round-trip failed: \(error)")
        }

        // SkillDraft is Equatable and Sendable but not Codable (intentionally)
        let draft = SkillDraft(name: "Draft", description: "desc", category: "cat", instructions: "inst")
        let draft2 = SkillDraft(name: "Draft", description: "desc", category: "cat", instructions: "inst")
        check(draft == draft2, "SkillDraft equality works")
        check(draft != SkillDraft(name: "Different", description: "d", category: "c", instructions: "i"), "SkillDraft inequality works")

        exit(failures == 0 ? 0 : 1)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}