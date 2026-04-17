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

    var pasteboardWriter: NSPasteboardWriting {
        switch kind {
        case let .file(reference):
            return reference.url as NSURL
        case let .link(url):
            return url as NSURL
        case let .text(string):
            return string as NSString
        }
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

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}

@MainActor
final class NotchShelfViewModel: ObservableObject {
    @Published private(set) var items: [NotchShelfItem] = []
    @Published var isDropTargeted = false
    @Published private(set) var selectedItemIDs: Set<UUID> = []

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

        switch persistenceService.loadResult() {
        case .missing:
            // No file yet — start empty; avoid creating a file until the user
            // actually puts something on the shelf.
            self.items = []
        case let .loaded(items):
            self.items = items
            // Re-save to prune records whose bookmarks could not be resolved.
            // Only do this when we know the file decoded cleanly, otherwise we
            // would overwrite a file that may still contain recoverable bytes.
            persistenceService.save(items)
        case .corrupted:
            // Preserve the on-disk payload so the user (or a future migration)
            // can try to recover it. Bug #9: previously we saved `[]` here,
            // silently destroying the shelf on any transient decode failure.
            self.items = []
        }
    }

    deinit {
        dropTask?.cancel()
        persistTask?.cancel()
    }

    var hasItems: Bool {
        !items.isEmpty
    }

    var selectedItems: [NotchShelfItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var primarySelectedItem: NotchShelfItem? {
        selectedItems.first
    }

    var previewableSelectedFileURLs: [URL] {
        selectedItems.compactMap { item in
            guard case let .file(reference) = item.kind else { return nil }
            return reference.url
        }
    }

    var canQuickLookSelection: Bool {
        !previewableSelectedFileURLs.isEmpty
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
        selectedItemIDs.remove(item.id)
        cleanupIfNeeded(item)
        clearThumbnailCache(for: item)
        debouncedPersist()
    }

    func clear() {
        let removedItems = items
        guard !removedItems.isEmpty else { return }

        items.removeAll()
        selectedItemIDs.removeAll()
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

    func selectOnly(_ item: NotchShelfItem) {
        selectedItemIDs = [item.id]
    }

    func toggleSelection(_ item: NotchShelfItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func select(ids: Set<UUID>) {
        let validIDs = Set(items.map(\.id))
        selectedItemIDs = ids.intersection(validIDs)
    }

    func isSelected(_ item: NotchShelfItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func dragItems(startingWith item: NotchShelfItem) -> [NotchShelfItem] {
        if selectedItemIDs.contains(item.id) {
            let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
            if !selectedItems.isEmpty {
                return selectedItems
            }
        }

        return [item]
    }

    func prepareSelectionForDrag(startingWith item: NotchShelfItem) {
        guard !selectedItemIDs.contains(item.id) else { return }
        selectOnly(item)
    }

    func moveItems(with ids: [UUID], to destinationIndex: Int) {
        guard !ids.isEmpty else { return }

        let draggedIDSet = Set(ids)
        let draggedItems = items.filter { draggedIDSet.contains($0.id) }
        guard !draggedItems.isEmpty else { return }

        let draggedIndexes = items.enumerated().compactMap { index, item in
            draggedIDSet.contains(item.id) ? index : nil
        }
        let remainingItems = items.filter { !draggedIDSet.contains($0.id) }
        let removedBeforeDestination = draggedIndexes.filter { $0 < destinationIndex }.count
        let adjustedDestination = destinationIndex - removedBeforeDestination
        let clampedDestination = max(0, min(adjustedDestination, remainingItems.count))

        var reorderedItems = remainingItems
        reorderedItems.insert(contentsOf: draggedItems, at: clampedDestination)

        guard reorderedItems != items else { return }

        items = reorderedItems
        // Bug #E: select only IDs that actually map to an item. Using the raw
        // input set would leak stale UUIDs (items deleted between selection
        // and drop) into selectedItemIDs, leaving an invisible selection.
        selectedItemIDs = Set(draggedItems.map(\.id))
        debouncedPersist()
    }

    func activateSelectedItems() {
        let actionableItems = selectedItems.filter {
            switch $0.kind {
            case .file, .link:
                return true
            case .text:
                return false
            }
        }

        if actionableItems.isEmpty, let item = primarySelectedItem {
            activate(item)
            return
        }

        actionableItems.forEach(activate)
    }

    func revealInFinder(_ item: NotchShelfItem) {
        guard case let .file(reference) = item.kind else { return }
        NSWorkspace.shared.activateFileViewerSelecting([reference.url])
    }

    func copySelectedItemsToPasteboard() {
        copyItemsToPasteboard(selectedItems)
    }

    func removeSelectedItems() {
        let itemsToRemove = selectedItems
        guard !itemsToRemove.isEmpty else { return }

        let removedIDs = Set(itemsToRemove.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        selectedItemIDs.removeAll()
        cleanupIfNeeded(itemsToRemove)
        clearThumbnailCache(for: itemsToRemove)
        debouncedPersist()
    }

    func merge(_ newItems: [NotchShelfItem]) {
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
        // Bug #2: select the VISUALLY topmost new item. Because we insert
        // `mergedItems.reversed()` at index 0, the topmost item on screen is
        // `mergedItems.last`, not `mergedItems.first`.
        if let topmostNewItem = mergedItems.last {
            selectedItemIDs = [topmostNewItem.id]
        }
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

    private func copyItemsToPasteboard(_ items: [NotchShelfItem]) {
        guard !items.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let writers = items.map(\.pasteboardWriter)
        if pasteboard.writeObjects(writers) {
            return
        }

        if items.count == 1,
           case let .text(string) = items[0].kind {
            pasteboard.setString(string, forType: .string)
        }
    }
}
