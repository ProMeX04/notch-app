import Foundation

public enum SkillSource: String, Codable, Sendable, Equatable {
    case builtin
    case user
    case generated
}

public struct SkillRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var category: String
    public var instructions: String
    public var createdAt: Date
    public var updatedAt: Date
    public var source: SkillSource
    public var isArchived: Bool

    public init(
        id: String,
        name: String,
        description: String,
        category: String,
        instructions: String,
        createdAt: Date,
        updatedAt: Date,
        source: SkillSource,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.instructions = instructions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.isArchived = isArchived
    }

    /// Stable id for the shipped “Getting Started” builtin skill.
    public static let gettingStartedBuiltinID = "skill.builtin.getting-started"
}

public struct SkillDraft: Equatable, Sendable {
    public var name: String
    public var description: String
    public var category: String
    public var instructions: String

    public init(
        name: String,
        description: String,
        category: String,
        instructions: String
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.instructions = instructions
    }
}

struct SkillV2Envelope: Codable, Sendable {
    var skills: [SkillRecord]
}
