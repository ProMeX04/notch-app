import AppKit
import Foundation

struct NotchShelfItem: Identifiable, Equatable {
    struct FileReference: Equatable {
        let url: URL
        let bookmarkData: Data
        let isTemporary: Bool
    }

    enum Kind: Equatable {
        case file(FileReference)
        case link(URL)
        case text(String)
    }

    let id: UUID
    let kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    var iconName: String {
        switch kind {
        case .file:
            return "doc.fill"
        case .link:
            return "link"
        case .text:
            return "text.alignleft"
        }
    }

    var title: String {
        switch kind {
        case let .file(reference):
            return reference.url.lastPathComponent
        case let .link(url):
            return url.host ?? url.absoluteString
        case let .text(string):
            let line = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .first ?? "Text"
            return line.isEmpty ? "Text" : String(line.prefix(60))
        }
    }

    var displayName: String {
        switch kind {
        case let .file(reference):
            return reference.url.lastPathComponent
        case let .link(url):
            if let host = url.host, !host.isEmpty {
                return host
            }
            return url.absoluteString
        case let .text(string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = trimmed.components(separatedBy: .newlines).first ?? "Text"
            return line.isEmpty ? "Text" : String(line.prefix(48))
        }
    }

    var subtitle: String {
        switch kind {
        case let .file(reference):
            return reference.url.path
        case let .link(url):
            return url.absoluteString
        case let .text(string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 80 ? String(trimmed.prefix(80)) + "..." : trimmed
        }
    }

    var fallbackPreviewImage: NSImage {
        switch kind {
        case let .file(reference):
            return NSWorkspace.shared.icon(forFile: reference.url.path)
        case .link:
            return NSImage(
                systemSymbolName: "link.circle.fill",
                accessibilityDescription: "Link"
            ) ?? NSImage()
        case .text:
            return NSImage(
                systemSymbolName: "text.alignleft",
                accessibilityDescription: "Text"
            ) ?? NSImage()
        }
    }

    var dragItemProvider: NSItemProvider {
        switch kind {
        case let .file(reference):
            return NSItemProvider(contentsOf: reference.url) ?? NSItemProvider(object: reference.url as NSURL)
        case let .link(url):
            return NSItemProvider(object: url as NSURL)
        case let .text(string):
            return NSItemProvider(object: string as NSString)
        }
    }

    var identityKey: String {
        switch kind {
        case let .file(reference):
            return "file:\(reference.url.standardizedFileURL.path)"
        case let .link(url):
            return "link:\(url.absoluteString)"
        case let .text(string):
            return "text:\(string)"
        }
    }

    var isTemporaryFile: Bool {
        if case let .file(reference) = kind {
            return reference.isTemporary
        }
        return false
    }

    var fileURL: URL? {
        if case let .file(reference) = kind {
            return reference.url
        }
        return nil
    }
}

@MainActor
final class NotchShelfViewModel: ObservableObject {
    @Published private(set) var items: [NotchShelfItem] = []
    @Published var isDropTargeted = false

    private let dropService: NotchShelfDropService
    private let persistenceService: NotchShelfPersistenceService
    private var dropTask: Task<Void, Never>?

    init(
        dropService: NotchShelfDropService = NotchShelfDropService(),
        persistenceService: NotchShelfPersistenceService = NotchShelfPersistenceService()
    ) {
        self.dropService = dropService
        self.persistenceService = persistenceService
        self.items = persistenceService.load()
        persistenceService.save(items)
    }

    deinit {
        dropTask?.cancel()
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        dropTask?.cancel()
        dropTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let newItems = await self.dropService.items(from: providers)
            guard !newItems.isEmpty else { return }
            await self.merge(newItems)
        }

        return true
    }

    func remove(_ item: NotchShelfItem) {
        items.removeAll { $0.id == item.id }
        cleanupIfNeeded(item)
        clearThumbnailCache(for: item)
        persist()
    }

    func clear() {
        let removedItems = items
        items.removeAll()
        cleanupIfNeeded(removedItems)
        clearThumbnailCache(for: removedItems)
        persist()
    }

    func shutdown() {
        dropTask?.cancel()
        persist()
    }

    func activate(_ item: NotchShelfItem) {
        switch item.kind {
        case let .file(reference):
            NSWorkspace.shared.open(reference.url)
        case let .link(url):
            NSWorkspace.shared.open(url)
        case let .text(string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    private func merge(_ newItems: [NotchShelfItem]) async {
        let existingKeys = Set(items.map(\.identityKey))
        var seenKeys = existingKeys
        var mergedItems: [NotchShelfItem] = []

        for item in newItems {
            let key = item.identityKey
            if seenKeys.contains(key) {
                cleanupIfNeeded(item)
                continue
            }

            mergedItems.append(item)
            seenKeys.insert(key)
        }

        guard !mergedItems.isEmpty else { return }
        items.insert(contentsOf: mergedItems.reversed(), at: 0)
        persist()
    }

    private func cleanupIfNeeded(_ item: NotchShelfItem) {
        guard item.isTemporaryFile, let fileURL = item.fileURL else { return }

        Task {
            await dropService.removeTemporaryFile(at: fileURL)
        }
    }

    private func cleanupIfNeeded(_ items: [NotchShelfItem]) {
        let temporaryURLs = items.compactMap { item -> URL? in
            guard item.isTemporaryFile else { return nil }
            return item.fileURL
        }

        guard !temporaryURLs.isEmpty else { return }

        Task {
            await dropService.removeTemporaryFiles(at: temporaryURLs)
        }
    }

    private func clearThumbnailCache(for item: NotchShelfItem) {
        guard let fileURL = item.fileURL else { return }

        Task {
            await NotchShelfThumbnailService.shared.clearCache(for: fileURL)
        }
    }

    private func clearThumbnailCache(for items: [NotchShelfItem]) {
        let fileURLs = items.compactMap(\.fileURL)
        guard !fileURLs.isEmpty else { return }

        Task {
            await NotchShelfThumbnailService.shared.clearCache(for: fileURLs)
        }
    }

    private func persist() {
        persistenceService.save(items)
    }
}
