import Foundation

enum AgentResultSource: String, Codable, Equatable {
    case geminiLive
    case unknown

    var displayName: String {
        switch self {
        case .geminiLive: return "Gemini Live"
        case .unknown: return "Agent"
        }
    }
}

enum AgentResultKind: Equatable {
    /// Raw markdown source.
    case text(String)
    /// External web URL.
    case link(URL)
    /// Existing local file URL.
    case file(URL)

    var rawKindName: String {
        switch self {
        case .text: return "text"
        case .link: return "link"
        case .file: return "file"
        }
    }
}

struct AgentResultItem: Identifiable, Equatable {
    let id: UUID
    let batchId: UUID
    let createdAt: Date
    var pinned: Bool
    let title: String?
    let kind: AgentResultKind
    /// True when the on-disk asset (image/file) lives under our managed
    /// `TemporaryFiles/` directory and should be cleaned up on remove.
    let isTemporaryAsset: Bool
    let source: AgentResultSource

    init(
        id: UUID = UUID(),
        batchId: UUID,
        createdAt: Date = Date(),
        pinned: Bool = false,
        title: String? = nil,
        kind: AgentResultKind,
        isTemporaryAsset: Bool = false,
        source: AgentResultSource = .geminiLive
    ) {
        self.id = id
        self.batchId = batchId
        self.createdAt = createdAt
        self.pinned = pinned
        self.title = title
        self.kind = kind
        self.isTemporaryAsset = isTemporaryAsset
        self.source = source
    }

    /// File URL for kinds that map to a local file on disk; nil otherwise.
    var localFileURL: URL? {
        switch kind {
        case let .file(url):
            return url
        case .text, .link:
            return nil
        }
    }

    var plainTextForCopy: String? {
        switch kind {
        case let .text(string):
            return string
        case let .link(url):
            return url.absoluteString
        case .file:
            return nil
        }
    }
}

// MARK: - Persistence Codable Record

struct PersistedAgentResultItem: Codable {
    enum Kind: Codable {
        case text(String)
        case image(path: String, isTemporary: Bool)
        case link(URL)
        case file(path: String, isTemporary: Bool)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case path
            case isTemporary
            case url
        }

        private enum KindTag: String, Codable {
            case text
            case image
            case link
            case file
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(KindTag.self, forKey: .type) {
            case .text:
                self = .text(try container.decode(String.self, forKey: .text))
            case .image:
                self = .image(
                    path: try container.decode(String.self, forKey: .path),
                    isTemporary: try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
                )
            case .link:
                self = .link(try container.decode(URL.self, forKey: .url))
            case .file:
                self = .file(
                    path: try container.decode(String.self, forKey: .path),
                    isTemporary: try container.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .text(string):
                try container.encode(KindTag.text, forKey: .type)
                try container.encode(string, forKey: .text)
            case let .image(path, isTemporary):
                try container.encode(KindTag.image, forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encode(isTemporary, forKey: .isTemporary)
            case let .link(url):
                try container.encode(KindTag.link, forKey: .type)
                try container.encode(url, forKey: .url)
            case let .file(path, isTemporary):
                try container.encode(KindTag.file, forKey: .type)
                try container.encode(path, forKey: .path)
                try container.encode(isTemporary, forKey: .isTemporary)
            }
        }
    }

    let id: UUID
    let batchId: UUID
    let createdAt: Date
    let pinned: Bool
    let title: String?
    let kind: Kind
    let source: String

    init(_ item: AgentResultItem) {
        self.id = item.id
        self.batchId = item.batchId
        self.createdAt = item.createdAt
        self.pinned = item.pinned
        self.title = item.title
        self.source = item.source.rawValue
        switch item.kind {
        case let .text(string):
            self.kind = .text(string)
        case let .link(url):
            self.kind = .link(url)
        case let .file(url):
            self.kind = .file(path: url.path, isTemporary: item.isTemporaryAsset)
        }
    }

    func toRuntime() -> AgentResultItem? {
        let resolvedSource = AgentResultSource(rawValue: source) ?? .unknown
        switch kind {
        case let .text(string):
            return AgentResultItem(
                id: id,
                batchId: batchId,
                createdAt: createdAt,
                pinned: pinned,
                title: title,
                kind: .text(string),
                isTemporaryAsset: false,
                source: resolvedSource
            )
        case let .link(url):
            return AgentResultItem(
                id: id,
                batchId: batchId,
                createdAt: createdAt,
                pinned: pinned,
                title: title,
                kind: .link(url),
                isTemporaryAsset: false,
                source: resolvedSource
            )
        case let .image(path, isTemporary):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AgentResultItem(
                id: id,
                batchId: batchId,
                createdAt: createdAt,
                pinned: pinned,
                title: title,
                kind: .file(url),
                isTemporaryAsset: isTemporary,
                source: resolvedSource
            )
        case let .file(path, isTemporary):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return AgentResultItem(
                id: id,
                batchId: batchId,
                createdAt: createdAt,
                pinned: pinned,
                title: title,
                kind: .file(url),
                isTemporaryAsset: isTemporary,
                source: resolvedSource
            )
        }
    }
}
