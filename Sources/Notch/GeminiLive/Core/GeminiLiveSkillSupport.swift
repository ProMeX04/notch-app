import Foundation
import NotchGeminiSkillStorage

struct SkillFrontmatter: Hashable, Sendable {
    let name: String
    let description: String
    let category: String
    let requiredTools: Set<GeminiTool>
    let usesMemory: Bool
    let version: String?
}

struct InstalledSkill: Identifiable, Hashable, Sendable {
    let recordId: String
    let metadata: SkillFrontmatter
    let instructions: String
    let rootURL: URL
    let source: SkillSource

    var id: String { recordId }
}

struct SkillSessionSnapshot: Sendable {
    let skillsById: [String: InstalledSkill]
    let enabledSkillIDs: [String]
    let effectiveTools: Set<GeminiTool>

    var activeSkills: [InstalledSkill] {
        enabledSkillIDs.compactMap { skillsById[$0] }
    }
}

enum SkillImportError: LocalizedError {
    case duplicateSkill(String)
    case invalidFrontmatter(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateSkill(name):
            return "A skill named \"\(name)\" is already installed."
        case let .invalidFrontmatter(message):
            return message
        }
    }
}



enum GeminiLiveStoragePaths {
    private static let preparedStorage: Void = {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: stateRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: skillsV2Root, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: skillsV2RenderedDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: agentAvatarsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
        } catch {
            // Best-effort setup: stores fall back to empty state if preparation fails.
        }
    }()

    static var stateRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch", isDirectory: true)
    }

    static var workspaceRoot: URL {
        stateRoot.appendingPathComponent("workspace", isDirectory: true)
    }

    static var skillsDirectory: URL {
        workspaceRoot.appendingPathComponent("skills", isDirectory: true)
    }

    /// Managed JSON-backed skills (`skills.json`) plus rendered `SKILL.md` snapshots under `skills-v2/rendered/`.
    static var skillsV2Root: URL {
        workspaceRoot.appendingPathComponent("skills-v2", isDirectory: true)
    }

    static var skillsV2StoreFile: URL {
        skillsV2Root.appendingPathComponent("skills.json", isDirectory: false)
    }

    /// Rendered SKILL.md snapshots for Gemini `read`; each skill id has its own subfolder containing `SKILL.md`.
    static var skillsV2RenderedDirectory: URL {
        skillsV2Root.appendingPathComponent("rendered", isDirectory: true)
    }

    static var screenshotsDirectory: URL {
        workspaceRoot.appendingPathComponent("screenshots", isDirectory: true)
    }

    static var agentAvatarsDirectory: URL {
        stateRoot.appendingPathComponent("agent-avatars", isDirectory: true)
    }

    static var transcriptsDirectory: URL {
        stateRoot.appendingPathComponent("transcripts", isDirectory: true)
    }



    static var memoryFile: URL {
        workspaceRoot.appendingPathComponent("MEMORY.md")
    }

    static var userFile: URL {
        workspaceRoot.appendingPathComponent("USER.md")
    }

    static var developmentDirectory: URL {
        stateRoot.appendingPathComponent("Development", isDirectory: true)
    }

    static var developmentAPIKeyFile: URL {
        developmentDirectory.appendingPathComponent("gemini-api-key.json")
    }

    static var developmentGeminiLiveClientTokenFile: URL {
        developmentDirectory.appendingPathComponent("gemini-live-client-token.json")
    }

    static var developmentNotchAccountAccessTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-access-token.json")
    }

    static var developmentNotchAccountRefreshTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-refresh-token.json")
    }

    static var developmentBraveSearchAPIKeyFile: URL {
        developmentDirectory.appendingPathComponent("brave-search-api-key.json")
    }

    static var execApprovalsFile: URL {
        stateRoot.appendingPathComponent("exec-approvals.json")
    }


    static var defaultExecWorkingDirectory: URL {
        workspaceRoot
    }

    static func prepare(fileManager: FileManager = .default) {
        _ = fileManager
        _ = preparedStorage
    }

    static func resolvedExecWorkingDirectory(from workingDirectory: String?) -> URL? {
        let trimmed = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return defaultExecWorkingDirectory
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    static func resolvedWorkspacePath(from path: String?, directoryHint: Bool? = nil) -> URL? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let candidate: URL
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            candidate = URL(fileURLWithPath: expanded, isDirectory: directoryHint ?? false)
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed, isDirectory: directoryHint ?? false)
        }

        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedWorkspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = resolvedWorkspaceRoot.path
        let candidatePath = resolvedCandidate.path
        guard candidatePath == workspacePath || candidatePath.hasPrefix(workspacePath + "/") else {
            return nil
        }
        return resolvedCandidate
    }

    static func workspaceRelativePath(for url: URL) -> String {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedWorkspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = resolvedWorkspaceRoot.path
        let filePath = resolvedURL.path
        guard filePath != workspacePath else { return "." }
        guard filePath.hasPrefix(workspacePath + "/") else { return filePath }
        return String(filePath.dropFirst(workspacePath.count + 1))
    }

    static func skillPromptLocation(for skill: InstalledSkill) -> String {
        let skillFileURL = skill.rootURL.appendingPathComponent("SKILL.md")
        return workspaceRelativePath(for: skillFileURL)
    }

}

final class SkillStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let skillsDirectory: URL
    init(fileManager: FileManager = .default, skillsDirectory: URL = GeminiLiveStoragePaths.skillsDirectory) {
        GeminiLiveStoragePaths.prepare(fileManager: fileManager)
        self.fileManager = fileManager
        self.skillsDirectory = skillsDirectory
        try? ensureSkillsDirectory()
    }

    func listInstalledSkills() -> [InstalledSkill] {
        do {
            try ensureSkillsDirectory()
            let userSkills = try userSkillRoots().compactMap(loadSkill(at:))
            return userSkills
                .sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
        } catch {
            return []
        }
    }

    func deleteSkill(named name: String) throws {
        let target = skillsDirectory.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func skillExists(named name: String) -> Bool {
        let target = skillsDirectory.appendingPathComponent(name, isDirectory: true)
        return fileManager.fileExists(atPath: target.path)
    }

    private func ensureSkillsDirectory() throws {
        try fileManager.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
    }

    private func userSkillRoots() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func loadSkill(at url: URL) -> InstalledSkill? {
        let skillFileURL = url.appendingPathComponent("SKILL.md")
        guard let content = try? String(contentsOf: skillFileURL, encoding: .utf8) else {
            return nil
        }
        guard let parsed = try? SkillFrontmatterParser.parse(content) else {
            return nil
        }
        let inferredSource: SkillSource = parsed.frontmatter.category.lowercased() == "builtin" ? .builtin : .user
        return InstalledSkill(
            recordId: url.lastPathComponent,
            metadata: parsed.frontmatter,
            instructions: parsed.instructions,
            rootURL: url,
            source: inferredSource
        )
    }

}

enum SkillFrontmatterParser {
    struct ParsedSkill {
        let frontmatter: SkillFrontmatter
        let instructions: String
    }

    static func isValidSkillIdentifier(_ value: String) -> Bool {
        let pattern = #"^[A-Za-z0-9_-]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    static func parse(_ content: String) throws -> ParsedSkill {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n"),
              let closingRange = normalized.range(of: "\n---\n") else {
            throw SkillImportError.invalidFrontmatter("SKILL.md must start with YAML frontmatter.")
        }

        let frontmatterBlock = String(normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<closingRange.lowerBound])
        let body = String(normalized[closingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        for line in frontmatterBlock.split(separator: "\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            fields[key] = stripWrappingQuotes(rawValue)
        }

        guard let name = requiredField("name", in: fields),
              let description = requiredField("description", in: fields) else {
            throw SkillImportError.invalidFrontmatter("SKILL.md must include name and description.")
        }

        let category = requiredField("category", in: fields) ?? "general"
        let requiredTools = try parseRequiredTools(fields["requiredTools"] ?? "[]")
        let usesMemory = parseBool(fields["memory"]) ?? false
        let version = fields["version"].flatMap { $0.isEmpty ? nil : $0 }
        let frontmatter = SkillFrontmatter(
            name: name,
            description: description,
            category: category,
            requiredTools: requiredTools,
            usesMemory: usesMemory,
            version: version
        )
        return ParsedSkill(frontmatter: frontmatter, instructions: body)
    }

    private static func requiredField(_ key: String, in fields: [String: String]) -> String? {
        guard let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func parseRequiredTools(_ raw: String) throws -> Set<GeminiTool> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            throw SkillImportError.invalidFrontmatter("requiredTools must be a JSON string array.")
        }

        var resolved: Set<GeminiTool> = []
        for value in decoded {
            guard let tool = GeminiTool(rawValue: value) else {
                throw SkillImportError.invalidFrontmatter("Unknown required tool \"\(value)\" in SKILL.md.")
            }
            resolved.insert(tool)
        }
        return resolved
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func stripWrappingQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

final class MemoryStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, fileURL: URL = GeminiLiveStoragePaths.memoryFile) {
        GeminiLiveStoragePaths.prepare(fileManager: fileManager)
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    func readMainMemory() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func saveMemory(_ content: String) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

final class UserStore: @unchecked Sendable {
    private let fileURL: URL

    init(fileURL: URL = GeminiLiveStoragePaths.userFile) {
        self.fileURL = fileURL
    }

    func readUserProfile() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func saveUserProfile(_ content: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

enum SkillPromptComposer {
    static func buildPromptSection(for skills: [InstalledSkill], canReadSkills: Bool) -> String {
        guard canReadSkills, !skills.isEmpty else { return "" }
        let sortedSkills = skills.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
        var lines: [String] = [
            "## Skills",
            "Before responding, scan the available skills below.",
            "If exactly one skill clearly matches the task, call `read` on its `location` before following it.",
            "Do not read a skill unless it is clearly relevant.",
            "<available_skills>"
        ]

        for skill in sortedSkills {
            lines.append("  <skill>")
            lines.append("    <name>\(escape(skill.metadata.name))</name>")
            lines.append("    <description>\(escape(skill.metadata.description))</description>")
            let skillLocation = GeminiLiveStoragePaths.skillPromptLocation(for: skill)
            lines.append("    <location>\(escape(skillLocation))</location>")
            lines.append("  </skill>")
        }

        lines.append("</available_skills>")
        return lines.joined(separator: "\n")
    }

    static func escape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
