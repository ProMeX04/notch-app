import AppKit
import Combine
import Foundation

enum AgentResultsPaths {
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
            .appendingPathComponent("AgentResults", isDirectory: true)
    }

    static var persistenceFileURL: URL {
        baseDirectory.appendingPathComponent("items.json")
    }

    static var temporaryFilesDirectory: URL {
        baseDirectory.appendingPathComponent("TemporaryFiles", isDirectory: true)
    }

    static func ensureDirectoriesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: temporaryFilesDirectory, withIntermediateDirectories: true)
    }

    /// Returns true when `url` lives under our managed temporary files dir.
    static func isManagedTemporaryFile(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = temporaryFilesDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        return normalized.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
    }
}

/// JSON file persistence for `AgentResultItem`s. Mirrors the shape of
/// `NotchShelfPersistenceService` so behavior (atomic write, lossy load) is
/// consistent across stores.
final class AgentResultPersistenceService {
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        fileURL: URL = AgentResultsPaths.persistenceFileURL
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load() -> [AgentResultItem] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([PersistedAgentResultItem].self, from: data) else {
            return []
        }
        return records.compactMap { $0.toRuntime() }
    }

    func save(_ items: [AgentResultItem]) {
        let records = items.map(PersistedAgentResultItem.init)
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
protocol AgentResultStoreControlling: AnyObject {
    func shutdown()
}

@MainActor
final class AgentResultStore: ObservableObject, AgentResultStoreControlling {
    static let shared = AgentResultStore()

    /// Newest items at index 0 (descending by `createdAt`).
    @Published private(set) var items: [AgentResultItem] = []
    /// Increments whenever a new batch is appended. Useful for window flash.
    @Published private(set) var batchAppendCount: Int = 0
    @Published var showingHistory = false

    private var pruneTimer: Timer?

    /// Cap & TTL constants per spec.
    private let nonPinnedCap = 50
    private let nonPinnedTTL: TimeInterval = 24 * 60 * 60

    private init() {
        AgentResultsPaths.ensureDirectoriesExist()
        discardPersistedResults()
        schedulePruneTimer()
    }

    deinit {
        // NOTE: We intentionally do not touch MainActor properties here.
        // The store is ephemeral; shutdown handles timer cleanup explicitly.
    }

    // MARK: - Mutations

    /// Appends a batch of items (already sharing a single `batchId`) and
    /// triggers cap/TTL pruning. Results are in-memory only.
    func appendBatch(_ newItems: [AgentResultItem]) {
        guard !newItems.isEmpty else { return }
        showingHistory = false
        items.insert(contentsOf: newItems, at: 0)
        batchAppendCount &+= 1
        prune(now: Date(), persist: false)
    }

    func togglePin(_ item: AgentResultItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
    }

    func setPinned(_ id: UUID, pinned: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned = pinned
    }

    func remove(_ item: AgentResultItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        cleanupTemporaryAsset(for: removed)
    }

    func clear() {
        let removed = items
        items.removeAll()
        for item in removed {
            cleanupTemporaryAsset(for: item)
        }
    }

    func clearNonPinned() {
        let pinnedItems = items.filter { $0.pinned }
        let removed = items.filter { !$0.pinned }
        items = pinnedItems
        for item in removed {
            cleanupTemporaryAsset(for: item)
        }
    }

    /// Call from `ApplicationCoordinator.stop()`.
    func shutdown() {
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    // MARK: - Cap / TTL

    private func prune(now: Date, persist: Bool) {
        var current = items
        var didChange = false

        // TTL: drop non-pinned items older than 24h.
        let cutoff = now.addingTimeInterval(-nonPinnedTTL)
        var keptAfterTTL: [AgentResultItem] = []
        var droppedTTL: [AgentResultItem] = []
        for item in current {
            if !item.pinned, item.createdAt < cutoff {
                droppedTTL.append(item)
            } else {
                keptAfterTTL.append(item)
            }
        }
        if !droppedTTL.isEmpty {
            current = keptAfterTTL
            didChange = true
            for dropped in droppedTTL {
                cleanupTemporaryAsset(for: dropped)
            }
        }

        // Cap: at most 50 non-pinned, dropping oldest first.
        let nonPinnedCount = current.lazy.filter { !$0.pinned }.count
        if nonPinnedCount > nonPinnedCap {
            var overflow = nonPinnedCount - nonPinnedCap
            // Iterate oldest first.
            let nonPinnedOldestFirst = current.enumerated()
                .filter { !$0.element.pinned }
                .sorted { $0.element.createdAt < $1.element.createdAt }
            var idsToDrop: Set<UUID> = []
            for (_, item) in nonPinnedOldestFirst {
                if overflow == 0 { break }
                idsToDrop.insert(item.id)
                overflow -= 1
            }
            if !idsToDrop.isEmpty {
                let droppedCap = current.filter { idsToDrop.contains($0.id) }
                current.removeAll { idsToDrop.contains($0.id) }
                didChange = true
                for dropped in droppedCap {
                    cleanupTemporaryAsset(for: dropped)
                }
            }
        }

        if didChange {
            items = current
        }
    }

    private func schedulePruneTimer() {
        pruneTimer?.invalidate()
        // Run every 30 minutes; cheap and avoids leaving 24h+ items lingering
        // in-memory even if no new batches arrive.
        let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.prune(now: Date(), persist: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    // MARK: - Temp file cleanup

    private func discardPersistedResults() {
        let fm = FileManager.default
        try? fm.removeItem(at: AgentResultsPaths.persistenceFileURL)
        try? fm.removeItem(at: AgentResultsPaths.temporaryFilesDirectory)
        AgentResultsPaths.ensureDirectoriesExist()
    }

    private func cleanupTemporaryAsset(for item: AgentResultItem) {
        guard item.isTemporaryAsset, let url = item.localFileURL else { return }
        guard AgentResultsPaths.isManagedTemporaryFile(url) else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: url)
    }
}

// MARK: - Grouping helpers

extension AgentResultStore {
    struct Batch: Identifiable {
        let id: UUID
        let createdAt: Date
        let source: AgentResultSource
        let items: [AgentResultItem]
    }

    var groupedBatches: [Batch] {
        var orderedIDs: [UUID] = []
        var grouped: [UUID: [AgentResultItem]] = [:]
        for item in items {
            if grouped[item.batchId] == nil {
                orderedIDs.append(item.batchId)
            }
            grouped[item.batchId, default: []].append(item)
        }
        return orderedIDs.compactMap { id in
            guard let group = grouped[id], let first = group.first else { return nil }
            return Batch(
                id: id,
                createdAt: first.createdAt,
                source: first.source,
                items: group
            )
        }
    }

    var visibleBatches: [Batch] {
        let batches = groupedBatches
        guard !showingHistory else { return batches }
        return Array(batches.prefix(1))
    }

    var hasHistoryBatches: Bool {
        groupedBatches.count > 1
    }
}
