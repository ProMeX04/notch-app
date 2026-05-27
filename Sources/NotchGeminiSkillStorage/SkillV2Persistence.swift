import Foundation

public final class SkillV2Persistence: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private let fileManager: FileManager
    private var records: [SkillRecord]

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.records = []
    }

    /// Load from disk if present; otherwise starts empty (caller seeds).
    public func loadIfPresent() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(SkillV2Envelope.self, from: data)
        records = decoded.skills
    }

    /// Replace the working set during an explicit reset or import.
    public func replaceWorkingSet(_ newRecords: [SkillRecord]) {
        lock.lock()
        defer { lock.unlock() }
        records = newRecords
    }

    public func snapshot() -> [SkillRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func upsert(_ record: SkillRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll { $0.id == id }
    }

    public func skill(id: String) -> SkillRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records.first(where: { $0.id == id })
    }

    /// Case-insensitive name match among non-archived skills.
    public func skill(named name: String) -> SkillRecord? {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.first {
            !$0.isArchived && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    public func saveToDisk() throws {
        lock.lock()
        let copy = records
        lock.unlock()

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = SkillV2Envelope(skills: copy)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }
}
