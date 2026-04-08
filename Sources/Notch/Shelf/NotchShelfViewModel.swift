import AppKit
import Foundation

struct NotchShelfItem: Identifiable, Equatable {
    private static let internalDragIdentityType = "dev.notch.shelf.identity"

    struct FileReference: Equatable {
        let url: URL
        let fileIdentity: String
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
    let identityOverride: String?

    init(id: UUID = UUID(), kind: Kind, identityOverride: String? = nil) {
        self.id = id
        self.kind = kind
        self.identityOverride = identityOverride
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

    var dragItemProvider: NSItemProvider {
        let provider: NSItemProvider

        switch kind {
        case let .file(reference):
            provider = NSItemProvider(object: reference.url as NSURL)
        case let .link(url):
            provider = NSItemProvider(object: url as NSURL)
        case let .text(string):
            provider = NSItemProvider(object: string as NSString)
        }

        let identityData = Data(identityKey.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.internalDragIdentityType,
            visibility: .ownProcess
        ) { completion in
            completion(identityData, nil)
            return nil
        }

        return provider
    }

    var identityKey: String {
        if let identityOverride {
            return identityOverride
        }

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

    static var internalDragIdentityTypeIdentifier: String {
        internalDragIdentityType
    }
}

// MARK: - Workspace Icon Cache

/// A lightweight, thread-safe cache for `NSWorkspace.icon(forFile:)` results.
/// This avoids repeated disk I/O on the main thread for the same file path.
final class WorkspaceIconCache: @unchecked Sendable {
    static let shared = WorkspaceIconCache()

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private let maxEntries = 120

    func icon(for path: String) -> NSImage {
        lock.lock()
        if let cached = cache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = NSWorkspace.shared.icon(forFile: path)

        lock.lock()
        if cache.count >= maxEntries {
            // Evict roughly a quarter on overflow.
            let toRemove = cache.count / 4
            var removed = 0
            for key in cache.keys {
                guard removed < toRemove else { break }
                cache.removeValue(forKey: key)
                removed += 1
            }
        }
        cache[path] = image
        lock.unlock()

        return image
    }

    func invalidate(path: String) {
        lock.lock()
        cache.removeValue(forKey: path)
        lock.unlock()
    }
}

@MainActor
final class NotchShelfViewModel: ObservableObject {
    @Published private(set) var items: [NotchShelfItem] = []
    @Published var isDropTargeted = false

    private let dropService: NotchShelfDropService
    private let persistenceService: NotchShelfPersistenceService
    private var dropTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?

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
        persistTask?.cancel()
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        dropTask?.cancel()
        dropTask = Task { [weak self] in
            guard let self else { return }
            let newItems = await self.dropService.items(from: providers)
            guard !newItems.isEmpty else { return }
            await MainActor.run {
                self.merge(newItems)
            }
        }

        return true
    }

    func remove(_ item: NotchShelfItem) {
        items.removeAll { $0.id == item.id }
        cleanupIfNeeded(item)
        clearThumbnailCache(for: item)
        debouncedPersist()
    }

    func clear() {
        let removedItems = items
        items.removeAll()
        cleanupIfNeeded(removedItems)
        clearThumbnailCache(for: removedItems)
        debouncedPersist()
    }

    func shutdown() {
        dropTask?.cancel()
        persistTask?.cancel()
        // Final synchronous persist on shutdown.
        persistenceService.save(items)
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

    private func merge(_ newItems: [NotchShelfItem]) {
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
        debouncedPersist()
    }

    /// Debounce persistence writes to avoid redundant I/O when many items
    /// are added/removed in quick succession (e.g. multi-file drop).
    private func debouncedPersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard !Task.isCancelled, let self else { return }
            self.persistenceService.save(self.items)
        }
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
}
