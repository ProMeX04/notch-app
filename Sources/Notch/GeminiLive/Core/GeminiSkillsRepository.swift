import Foundation
import NotchGeminiSkillStorage

/// Bridges `skills-v2/skills.json` with rendered markdown for the `read` tool.
final class GeminiSkillsRepository: @unchecked Sendable {
    private let persistence: SkillV2Persistence
    private let renderedSkillsRoot: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        storeFileURL: URL = GeminiLiveStoragePaths.skillsV2StoreFile,
        renderedSkillsRoot: URL = GeminiLiveStoragePaths.skillsV2RenderedDirectory
    ) {
        GeminiLiveStoragePaths.prepare(fileManager: fileManager)
        self.fileManager = fileManager
        self.renderedSkillsRoot = renderedSkillsRoot
        self.persistence = SkillV2Persistence(fileURL: storeFileURL, fileManager: fileManager)

        bootstrapPersistenceBestEffort()
        seedGettingStartedIfNeeded()
        try? persistence.saveToDisk()
        try? synchronizeRenderedSnapshots()
    }

    private func bootstrapPersistenceBestEffort() {
        do {
            try persistence.loadIfPresent()
        } catch {
            persistence.replaceWorkingSet([])
        }
        let empty = persistence.snapshot().filter { !$0.isArchived }.isEmpty
        if empty {
            let seed = SkillRecord.gettingStartedSeed()
            try? persistence.upsert(seed)
            try? persistence.saveToDisk()
        }
    }

    func seedGettingStartedIfNeeded() {
        var working = persistence.snapshot()
        let hasGettingStarted = working.contains { $0.id == SkillRecord.gettingStartedBuiltinID && !$0.isArchived }
        if hasGettingStarted { return }
        let seed = SkillRecord.gettingStartedSeed()
        working.append(seed)
        persistence.replaceWorkingSet(working)
        try? persistence.saveToDisk()
        try? synchronizeRenderedSnapshots(recordsHint: working)
    }

    func record(id: String) -> SkillRecord? {
        persistence.skill(id: id)
    }

    func record(named name: String) -> SkillRecord? {
        persistence.skill(named: name)
    }

    func allRecords(includeArchived: Bool = false) -> [SkillRecord] {
        persistence.snapshot().filter { includeArchived || !$0.isArchived }
    }

    private func validateDraft(_ draft: SkillDraft, excludingRecordID: String?, requireInstructions: Bool = true) throws {
        let outcome = SkillDraftValidator.validate(
            draft: draft,
            existingRecords: persistence.snapshot(),
            excludingRecordID: excludingRecordID,
            requireNonEmptyInstructions: requireInstructions
        )
        if case let .failure(error) = outcome {
            throw GeminiSkillsRepositoryError.validation(error)
        }
    }

    func listInstalledSkillsSorted() throws -> [InstalledSkill] {
        try synchronizeRenderedSnapshots()
        let active = persistence.snapshot().filter { !$0.isArchived }
        return try active
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { try installedSkill(for: $0) }
    }

    func installedSkill(for record: SkillRecord) throws -> InstalledSkill {
        let folder = renderedSkillsRoot.appendingPathComponent(record.id, isDirectory: true)
        return InstalledSkill(
            recordId: record.id,
            metadata: SkillFrontmatter(
                name: record.name,
                description: record.description,
                category: record.category,
                requiredTools: [],
                usesMemory: false,
                version: nil
            ),
            instructions: record.instructions,
            rootURL: folder,
            source: record.source
        )
    }

    @discardableResult
    func createSkill(draft: SkillDraft, source: SkillSource) throws -> SkillRecord {
        let now = Date()
        let record = SkillRecord(
            id: UUID().uuidString,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "general" : draft.category.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: draft.instructions,
            createdAt: now,
            updatedAt: now,
            source: source,
            isArchived: false
        )
        try validateDraft(
            SkillDraft(
                name: record.name,
                description: record.description,
                category: record.category,
                instructions: record.instructions
            ),
            excludingRecordID: nil
        )
        try persistence.upsert(record)
        try persistence.saveToDisk()
        try render(record)
        return record
    }

    func updateSkill(id: String, draft: SkillDraft, allowUpdatingBuiltin: Bool = false) throws -> SkillRecord {
        guard let existing = persistence.skill(id: id) else { throw GeminiSkillsRepositoryError.notFound }
        if existing.source == .builtin, !allowUpdatingBuiltin {
            throw GeminiSkillsRepositoryError.cannotMutateBuiltin
        }

        let next = SkillRecord(
            id: existing.id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? existing.category : draft.category.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: draft.instructions,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            source: existing.source,
            isArchived: existing.isArchived
        )

        try validateDraft(
            SkillDraft(
                name: next.name,
                description: next.description,
                category: next.category,
                instructions: next.instructions
            ),
            excludingRecordID: id
        )

        try persistence.upsert(next)
        try persistence.saveToDisk()
        try render(next)
        return next
    }

    func duplicateSkill(id: String) throws -> SkillRecord {
        guard let existing = persistence.skill(id: id) else { throw GeminiSkillsRepositoryError.notFound }
        let draft = SkillDraft(
            name: Self.duplicateName(from: existing.name, taken: persistence.snapshot().map(\.name)),
            description: existing.description,
            category: existing.category == "builtin" ? "general" : existing.category,
            instructions: existing.instructions
        )
        return try createSkill(draft: draft, source: .user)
    }

    func deleteSkill(id: String) throws {
        guard let existing = persistence.skill(id: id) else { return }
        if existing.source == .builtin {
            throw GeminiSkillsRepositoryError.cannotMutateBuiltin
        }
        try persistence.delete(id: id)
        try persistence.saveToDisk()
        try? removeRendered(id: existing.id)
    }

    func applyToolWrite(action: SkillWriterToolAction, draft: SkillDraft, skillId: String?) throws -> SkillRecord {
        switch action {
        case .create:
            return try createSkill(draft: draft, source: .generated)
        case .update:
            guard let sid = skillId else { throw GeminiSkillsRepositoryError.notFound }
            return try updateSkill(id: sid, draft: draft, allowUpdatingBuiltin: false)
        }
    }

    /// Merges a parsed SKILL.md (folder or extracted package root) into managed JSON storage.
    @discardableResult
    func importParsedSkill(parsed: SkillFrontmatterParser.ParsedSkill, replacingExistingNamed: Bool) throws -> SkillRecord {
        try synchronizeRenderedSnapshots()
        var existing = persistence.snapshot()
        let name = parsed.frontmatter.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = existing.firstIndex(where: {
            !$0.isArchived &&
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) ==
                .orderedSame
        }) {
            guard replacingExistingNamed else {
                throw SkillImportError.duplicateSkill(parsed.frontmatter.name)
            }
            let previous = existing[idx]
            try? removeRendered(id: previous.id)
            try persistence.delete(id: previous.id)
            existing = persistence.snapshot()
        }

        let now = Date()
        let record = SkillRecord(
            id: UUID().uuidString,
            name: parsed.frontmatter.name,
            description: parsed.frontmatter.description,
            category: parsed.frontmatter.category,
            instructions: parsed.instructions,
            createdAt: now,
            updatedAt: now,
            source: .user,
            isArchived: false
        )
        try validateDraft(
            SkillDraft(
                name: record.name,
                description: record.description,
                category: record.category,
                instructions: record.instructions
            ),
            excludingRecordID: nil
        )
        try persistence.upsert(record)
        try persistence.saveToDisk()
        try render(record)
        return record
    }

    /// Rewrites rendered markdown snapshots for active skills under `skills-v2/rendered/<id>/SKILL.md`.
    func synchronizeRenderedSnapshots(recordsHint: [SkillRecord]? = nil) throws {
        let active = recordsHint ?? persistence.snapshot().filter { !$0.isArchived }
        try fileManager.createDirectory(at: renderedSkillsRoot, withIntermediateDirectories: true)
        for record in active {
            try render(record)
        }
        pruneOrphanRenderedFolders(activeRecords: active)
    }

    private func pruneOrphanRenderedFolders(activeRecords: [SkillRecord]) {
        let allowed = Set(activeRecords.map(\.id))
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: renderedSkillsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for dir in dirs {
            let component = dir.lastPathComponent
            guard !allowed.contains(component) else { continue }
            try? fileManager.removeItem(at: dir)
        }
    }

    private func removeRendered(id: String) throws {
        let dir = renderedSkillsRoot.appendingPathComponent(id, isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    private func render(_ record: SkillRecord) throws {
        let dir = renderedSkillsRoot.appendingPathComponent(record.id, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("SKILL.md", isDirectory: false)
        try Self.renderMarkdownFile(for: record).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func renderMarkdownFile(for record: SkillRecord) -> String {
        let name = yamlQuote(record.name)
        let description = yamlQuote(record.description)
        let category = yamlQuote(record.category)
        let body = record.instructions
        return """
        ---
        name: \(name)
        description: \(description)
        category: \(category)
        requiredTools: []
        memory: false
        ---

        \(body)
        """
    }

    private static func yamlQuote(_ raw: String) -> String {
        let needsQuotes =
            raw.isEmpty ||
            raw.contains(where: { $0 == ":" || $0 == "#" || $0 == "'" || $0 == "\"" }) ||
            raw.contains("\n") ||
            raw.contains("\r")

        guard needsQuotes else { return raw }
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func duplicateName(from name: String, taken: [String]) -> String {
        let basePrefix = "\(name) copy"
        var candidate = "\(basePrefix)"
        let set = Set(taken.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        var index = 2
        while set.contains(candidate.lowercased()) {
            candidate = "\(basePrefix) \(index)"
            index += 1
        }
        return candidate
    }
}

enum GeminiSkillsRepositoryError: LocalizedError {
    case validation(SkillDraftValidationError)
    case notFound
    case cannotMutateBuiltin

    var errorDescription: String? {
        switch self {
        case let .validation(underlying):
            return underlying.errorDescription
        case .notFound: return "That skill couldn't be found."
        case .cannotMutateBuiltin: return "Built-in skills can't be edited or deleted; duplicate instead."
        }
    }
}
