import Foundation

func notchShelfFileIdentity(for url: URL) -> String {
    let normalizedURL = ((url as NSURL).filePathURL ?? url)
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let resourceKeys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
    let resourceValues = try? normalizedURL.resourceValues(forKeys: resourceKeys)

    if let fileID = resourceValues?.fileResourceIdentifier,
       let volumeID = resourceValues?.volumeIdentifier {
        return "fileid:\(String(describing: volumeID))::\(String(describing: fileID))"
    }

    return "path:\(normalizedURL.path)"
}

enum NotchShelfPaths {
    static var baseDirectory: URL {
        let fileManager = FileManager.default
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        return supportDirectory
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    static var persistenceFileURL: URL {
        baseDirectory.appendingPathComponent("items.json")
    }

    static var temporaryFilesDirectory: URL {
        baseDirectory.appendingPathComponent("TemporaryFiles", isDirectory: true)
    }
}

struct Bookmark: Sendable, Equatable, Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(url: URL) throws {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = resourceValues?.isDirectory == true

        if isDirectory,
           let plainBookmark = try? url.bookmarkData(
               options: [],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            self.data = plainBookmark
            return
        }

        self.data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve() -> (url: URL?, refreshedData: Data?) {
        var isStale = false

        let resolution = resolveURLAndStaleness()
        guard let url = resolution.url else {
            return (nil, nil)
        }

        isStale = resolution.isStale

        if isStale,
           let refreshedData = try? url.bookmarkData(
               options: refreshOptions(for: url),
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            return (url, refreshedData)
        }

        return (url, nil)
    }

    private func resolveURLAndStaleness() -> (url: URL?, isStale: Bool) {
        var securityScopedStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &securityScopedStale
        ) {
            return (url, securityScopedStale)
        }

        var plainStale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &plainStale
        )
        return (url, plainStale)
    }

    private func refreshOptions(for url: URL) -> URL.BookmarkCreationOptions {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true ? [] : [.withSecurityScope]
    }
}

final class NotchShelfPersistenceService {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        fileURL: URL = NotchShelfPaths.persistenceFileURL
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() -> [NotchShelfItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([PersistedShelfItem].self, from: data) else {
            return []
        }

        return records.compactMap(restoreItem)
    }

    func save(_ items: [NotchShelfItem]) {
        let records = items.map(PersistedShelfItem.init)

        guard let data = try? encoder.encode(records) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    private func restoreItem(from record: PersistedShelfItem) -> NotchShelfItem? {
        switch record.kind {
        case let .text(string):
            return NotchShelfItem(id: record.id, kind: .text(string))
        case let .link(url):
            return NotchShelfItem(id: record.id, kind: .link(url))
        case let .file(bookmarkData, isTemporary):
            let bookmark = Bookmark(data: bookmarkData)
            let resolved = bookmark.resolve()

            guard let url = resolved.url,
                  fileManager.fileExists(atPath: url.path) else {
                return nil
            }

            return NotchShelfItem(
                id: record.id,
                kind: .file(
                    .init(
                        url: url.standardizedFileURL,
                        fileIdentity: notchShelfFileIdentity(for: url),
                        bookmarkData: resolved.refreshedData ?? bookmarkData,
                        isTemporary: isTemporary
                    )
                )
            )
        }
    }
}

private struct PersistedShelfItem: Codable {
    enum Kind: Codable {
        case file(bookmarkData: Data, isTemporary: Bool)
        case text(String)
        case link(URL)

        private enum CodingKeys: String, CodingKey {
            case type
            case bookmarkData
            case isTemporary
            case text
            case url
        }

        private enum KindTag: String, Codable {
            case file
            case text
            case link
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(KindTag.self, forKey: .type)

            switch type {
            case .file:
                self = .file(
                    bookmarkData: try container.decode(Data.self, forKey: .bookmarkData),
                    isTemporary: try container.decode(Bool.self, forKey: .isTemporary)
                )
            case .text:
                self = .text(try container.decode(String.self, forKey: .text))
            case .link:
                self = .link(try container.decode(URL.self, forKey: .url))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .file(bookmarkData, isTemporary):
                try container.encode(KindTag.file, forKey: .type)
                try container.encode(bookmarkData, forKey: .bookmarkData)
                try container.encode(isTemporary, forKey: .isTemporary)
            case let .text(string):
                try container.encode(KindTag.text, forKey: .type)
                try container.encode(string, forKey: .text)
            case let .link(url):
                try container.encode(KindTag.link, forKey: .type)
                try container.encode(url, forKey: .url)
            }
        }
    }

    let id: UUID
    let kind: Kind

    init(_ item: NotchShelfItem) {
        self.id = item.id

        switch item.kind {
        case let .text(string):
            self.kind = .text(string)
        case let .link(url):
            self.kind = .link(url)
        case let .file(reference):
            self.kind = .file(
                bookmarkData: reference.bookmarkData,
                isTemporary: reference.isTemporary
            )
        }
    }
}
