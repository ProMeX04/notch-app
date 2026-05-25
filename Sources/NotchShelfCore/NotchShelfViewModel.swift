import AppKit
import CryptoKit
import Foundation
import Security
import UniformTypeIdentifiers

public struct NotchShelfItem: Identifiable, Equatable, Sendable {
    private static let internalDragIdentityType = "dev.notch.shelf.identity"

    public struct FileReference: Equatable, Sendable {
        public let url: URL
        public let fileIdentity: String
        public let bookmarkData: Data
        public let isTemporary: Bool

        public init(url: URL, fileIdentity: String, bookmarkData: Data, isTemporary: Bool) {
            self.url = url
            self.fileIdentity = fileIdentity
            self.bookmarkData = bookmarkData
            self.isTemporary = isTemporary
        }
    }

    public enum Kind: Equatable, Sendable {
        case file(FileReference)
        case link(URL)
        case text(String)
    }

    public let id: UUID
    public let kind: Kind
    let identityOverride: String?
    public let driveFileID: String?
    public let driveIsPublic: Bool
    public let driveUploadedAt: Date?

    public init(id: UUID = UUID(), kind: Kind, identityOverride: String? = nil, driveFileID: String? = nil, driveIsPublic: Bool = false, driveUploadedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.identityOverride = identityOverride
        self.driveFileID = driveFileID
        self.driveIsPublic = driveIsPublic
        self.driveUploadedAt = driveUploadedAt
    }

    public func withDriveFileID(_ fileID: String?) -> NotchShelfItem {
        NotchShelfItem(id: id, kind: kind, identityOverride: identityOverride, driveFileID: fileID, driveIsPublic: driveIsPublic, driveUploadedAt: driveUploadedAt)
    }

    public func withDriveIsPublic(_ isPublic: Bool) -> NotchShelfItem {
        NotchShelfItem(id: id, kind: kind, identityOverride: identityOverride, driveFileID: driveFileID, driveIsPublic: isPublic, driveUploadedAt: driveUploadedAt)
    }

    public func withDriveUploadedAt(_ uploadedAt: Date?) -> NotchShelfItem {
        NotchShelfItem(id: id, kind: kind, identityOverride: identityOverride, driveFileID: driveFileID, driveIsPublic: driveIsPublic, driveUploadedAt: uploadedAt)
    }

    public enum ItemDriveState: String {
        case local
        case synced
        case syncedPublic
        case modified
        case orphaned
    }

    public var driveState: ItemDriveState {
        guard driveFileID != nil else {
            return .local
        }

        switch kind {
        case .file(let reference):
            let bookmark = Bookmark(data: reference.bookmarkData)
            guard let url = bookmark.resolve().url else {
                return .orphaned
            }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                return .orphaned
            }

            if let driveUploadedAt = driveUploadedAt {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                if let modDate = attributes?[.modificationDate] as? Date,
                   modDate.timeIntervalSince(driveUploadedAt) > 1 {
                    return .modified
                }
            }

        case .text, .link:
            break
        }

        return driveIsPublic ? .syncedPublic : .synced
    }

    public var isDriveUploadEligible: Bool {
        let state = driveState
        return state == .local || state == .modified
    }

    public var iconName: String {
        switch kind {
        case .file:
            return "doc.fill"
        case .link:
            return "link"
        case .text:
            return "text.alignleft"
        }
    }

    public var title: String {
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

    public var displayName: String {
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

    public var subtitle: String {
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

    public var dragItemProvider: NSItemProvider {
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

    public var identityKey: String {
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

    public var isTemporaryFile: Bool {
        if case let .file(reference) = kind {
            return reference.isTemporary
        }
        return false
    }

    public var fileURL: URL? {
        if case let .file(reference) = kind {
            return reference.url
        }
        return nil
    }

    public var pasteboardWriter: NSPasteboardWriting {
        switch kind {
        case let .file(reference):
            return reference.url as NSURL
        case let .link(url):
            return url as NSURL
        case let .text(string):
            return string as NSString
        }
    }

    public static var internalDragIdentityTypeIdentifier: String {
        internalDragIdentityType
    }
}

// MARK: - Workspace Icon Cache

/// A lightweight, thread-safe cache for `NSWorkspace.icon(forFile:)` results.
/// This avoids repeated disk I/O on the main thread for the same file path.
public final class WorkspaceIconCache: @unchecked Sendable {
    public static let shared = WorkspaceIconCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    public func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }

    public func invalidate(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    public func clearAll() {
        cache.removeAllObjects()
    }
}

@MainActor
public final class NotchShelfViewModel: ObservableObject {
    @Published public private(set) var items: [NotchShelfItem] = [] {
        didSet {
            refreshDriveStates(force: true)
        }
    }
    @Published public private(set) var cachedDriveStates: [UUID: NotchShelfItem.ItemDriveState] = [:]
    @Published public var isDropTargeted = false
    @Published public private(set) var selectedItemIDs: Set<UUID> = []

    // Google Drive Integration
    @Published public private(set) var isGoogleDriveConnected = false
    @Published public private(set) var isUploadingToDrive = false
    @Published public private(set) var uploadingItemIDs: Set<UUID> = []
    @Published public private(set) var uploadProgresses: [UUID: Double] = [:]
    @Published public var driveUploadMessage: String?
    @Published public private(set) var driveUploadError: String?
    @Published public private(set) var itemsInProgress: Set<UUID> = []
    @Published public private(set) var itemErrors: [UUID: String] = [:]
    public var portalBaseURLProvider: (() -> URL)?
    public var onConnectGoogleDriveRequested: ((String, String) -> Void)?
    var pendingGoogleDriveAuthState: String?

    private let dropService: NotchShelfDropService
    private let persistenceService: NotchShelfPersistenceService
    private var dropTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var driveOperationTasks: [UUID: Task<Void, Never>] = [:]
    private var driveHandoffTask: Task<Void, Never>?
    private var isCompletingDriveHandoff = false
    private var lastRefreshTime: Date = .distantPast
    private var pendingGoogleDriveAuthStateExpiresAt: Date?
    private var pendingGoogleDriveCodeVerifier: String?
    private static let googleDriveAuthStateLifetime: TimeInterval = 10 * 60
    private static let invalidGoogleDriveCallbackMessage = "Kết nối thất bại: Phiên xác thực Google Drive không hợp lệ hoặc đã hết hạn."

    public convenience init() {
        self.init(
            dropService: NotchShelfDropService(),
            persistenceService: NotchShelfPersistenceService()
        )
    }

    init(
        dropService: NotchShelfDropService = NotchShelfDropService(),
        persistenceService: NotchShelfPersistenceService = NotchShelfPersistenceService()
    ) {
        self.dropService = dropService
        self.persistenceService = persistenceService
        self.isGoogleDriveConnected = NotchGoogleDriveService.shared.isConnected

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

        // Populate initial cache estimates without blocking
        var initialStates: [UUID: NotchShelfItem.ItemDriveState] = [:]
        for item in self.items {
            if item.driveFileID == nil {
                initialStates[item.id] = .local
            } else {
                initialStates[item.id] = item.driveIsPublic ? .syncedPublic : .synced
            }
        }
        self.cachedDriveStates = initialStates
        self.refreshDriveStates(force: true)
    }

    deinit {
        dropTask?.cancel()
        persistTask?.cancel()
        refreshTask?.cancel()
        driveHandoffTask?.cancel()
        driveOperationTasks.values.forEach { $0.cancel() }
    }

    public var hasItems: Bool {
        !items.isEmpty
    }

    public var selectedItems: [NotchShelfItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    public var primarySelectedItem: NotchShelfItem? {
        selectedItems.first
    }

    public var previewableSelectedFileURLs: [URL] {
        selectedItems.compactMap { item in
            guard case let .file(reference) = item.kind else { return nil }
            return reference.url
        }
    }

    public var canQuickLookSelection: Bool {
        !previewableSelectedFileURLs.isEmpty
    }

    public func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        dropTask?.cancel()
        dropTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let newItems = await self.dropService.items(from: providers)
            guard !newItems.isEmpty else { return }
            self.merge(newItems)
        }

        return true
    }

    public func remove(_ item: NotchShelfItem) {
        cancelDriveOperations(for: [item.id])
        items.removeAll { $0.id == item.id }
        selectedItemIDs.remove(item.id)
        cleanupIfNeeded(item)
        clearThumbnailCache(for: item)
        debouncedPersist()
    }

    public func clear() {
        let removedItems = items
        guard !removedItems.isEmpty else { return }

        cancelDriveOperations(for: Set(removedItems.map(\.id)))
        items.removeAll()
        selectedItemIDs.removeAll()
        cleanupIfNeeded(removedItems)
        clearThumbnailCache(for: removedItems)
        debouncedPersist()
    }

    public func shutdown() {
        dropTask?.cancel()
        persistTask?.cancel()
        driveHandoffTask?.cancel()
        driveOperationTasks.values.forEach { $0.cancel() }
        driveOperationTasks.removeAll()
        // Final synchronous persist on shutdown.
        persistenceService.save(items)
    }

    public func activate(_ item: NotchShelfItem) {
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

    public func selectOnly(_ item: NotchShelfItem) {
        selectedItemIDs = [item.id]
    }

    public func toggleSelection(_ item: NotchShelfItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    public func clearSelection() {
        selectedItemIDs.removeAll()
    }

    public func select(ids: Set<UUID>) {
        let validIDs = Set(items.map(\.id))
        selectedItemIDs = ids.intersection(validIDs)
    }

    public func isSelected(_ item: NotchShelfItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    public func dragItems(startingWith item: NotchShelfItem) -> [NotchShelfItem] {
        if selectedItemIDs.contains(item.id) {
            let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
            if !selectedItems.isEmpty {
                return selectedItems
            }
        }

        return [item]
    }

    public func prepareSelectionForDrag(startingWith item: NotchShelfItem) {
        guard !selectedItemIDs.contains(item.id) else { return }
        selectOnly(item)
    }

    public func moveItems(with ids: [UUID], to destinationIndex: Int) {
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

    public func activateSelectedItems() {
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

    public func revealInFinder(_ item: NotchShelfItem) {
        guard case let .file(reference) = item.kind else { return }
        NSWorkspace.shared.activateFileViewerSelecting([reference.url])
    }

    public func copySelectedItemsToPasteboard() {
        copyItemsToPasteboard(selectedItems)
    }

    public func removeSelectedItems() {
        let itemsToRemove = selectedItems
        guard !itemsToRemove.isEmpty else { return }

        let removedIDs = Set(itemsToRemove.map(\.id))
        cancelDriveOperations(for: removedIDs)
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

        if isGoogleDriveConnected && UserDefaults.standard.bool(forKey: "notchShelfGoogleDriveAutoUploadEnabled") {
            uploadItemsToDrive(mergedItems)
        }
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

    // MARK: - Google Drive Methods

    public func connectGoogleDrive() {
        driveHandoffTask?.cancel()
        let state = Self.makeGoogleDriveAuthState()
        let verifier = Self.makeGoogleDriveAuthState()
        pendingGoogleDriveAuthState = state
        pendingGoogleDriveAuthStateExpiresAt = Date().addingTimeInterval(Self.googleDriveAuthStateLifetime)
        pendingGoogleDriveCodeVerifier = verifier
        driveUploadError = nil
        onConnectGoogleDriveRequested?(state, Self.googleDriveCodeChallenge(for: verifier))
    }

    public func disconnectGoogleDrive() {
        driveHandoffTask?.cancel()
        driveHandoffTask = nil
        isCompletingDriveHandoff = false
        updateDriveActivityState()
        NotchGoogleDriveService.shared.clearCredentials()
        clearPendingGoogleDriveAuthState()
        isGoogleDriveConnected = false
        driveUploadMessage = nil
        driveUploadError = nil
    }

    public func handleGoogleDriveCallback(accessToken: String?, refreshToken: String?, expiresIn: String?, error: String?, state: String?, handoffToken: String? = nil) {
        guard let codeVerifier = pendingGoogleDriveCodeVerifier,
              consumePendingGoogleDriveAuthState(state) else {
            driveUploadError = Self.invalidGoogleDriveCallbackMessage
            return
        }

        if let error = error {
            driveUploadError = "Kết nối thất bại: \(error)"
            return
        }

        if let handoffToken = handoffToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !handoffToken.isEmpty {
            completeGoogleDriveHandoff(handoffToken, codeVerifier: codeVerifier)
            return
        }

        driveUploadError = "Kết nối thất bại: Phản hồi Google Drive không sử dụng handoff an toàn."
    }

    private func completeGoogleDriveHandoff(_ handoffToken: String, codeVerifier: String) {
        guard let portalBaseURL = portalBaseURLProvider?() else {
            driveUploadError = "Không thể lấy cấu hình URL hệ thống."
            return
        }

        isCompletingDriveHandoff = true
        updateDriveActivityState()
        driveUploadError = nil
        driveUploadMessage = "Đang hoàn tất liên kết Google Drive..."

        driveHandoffTask = Task {
            do {
                let payload = try await NotchGoogleDriveService.shared.exchangeHandoffToken(
                    handoffToken,
                    codeVerifier: codeVerifier,
                    portalBaseURL: portalBaseURL
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self.isCompletingDriveHandoff = false
                    self.updateDriveActivityState()
                    self.completeGoogleDriveConnection(
                        accessToken: payload.accessToken,
                        refreshToken: payload.refreshToken,
                        expiresIn: payload.expiresIn
                    )
                }
            } catch {
                await MainActor.run {
                    self.isCompletingDriveHandoff = false
                    self.updateDriveActivityState()
                    self.driveUploadMessage = nil
                    if !Task.isCancelled {
                        self.driveUploadError = "Kết nối thất bại: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func completeGoogleDriveConnection(accessToken: String, refreshToken: String?, expiresIn: Int?) {
        let service = NotchGoogleDriveService.shared
        let expiryDate: Date
        if let expiresIn {
            expiryDate = Date().addingTimeInterval(Double(expiresIn))
        } else {
            expiryDate = Date().addingTimeInterval(3600)
        }
        guard service.storeCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAtDate: expiryDate
        ) else {
            isGoogleDriveConnected = false
            driveUploadMessage = nil
            driveUploadError = "Kết nối thất bại: Không thể lưu thông tin xác thực an toàn."
            return
        }

        isGoogleDriveConnected = true
        driveUploadError = nil
        driveUploadMessage = "Đã liên kết Google Drive thành công!"

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if driveUploadMessage == "Đã liên kết Google Drive thành công!" {
                driveUploadMessage = nil
            }
        }
    }

    public func copyDriveLink(_ item: NotchShelfItem) {
        guard let fileId = item.driveFileID else { return }
        let link = "https://drive.google.com/file/d/\(fileId)/view?usp=drivesdk"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([link as NSString])
        driveUploadMessage = "Đã sao chép liên kết Google Drive!"

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self.driveUploadMessage == "Đã sao chép liên kết Google Drive!" {
                    self.driveUploadMessage = nil
                }
            }
        }
    }

    public func uploadItemsToDrive(_ itemsToUpload: [NotchShelfItem]) {
        guard !itemsToUpload.isEmpty else { return }
        guard let portalBaseURL = portalBaseURLProvider?() else {
            driveUploadError = "Không thể lấy cấu hình URL hệ thống."
            return
        }

        let requestedIDs = Set(itemsToUpload.map(\.id))
        let reservedItems = items.filter {
            requestedIDs.contains($0.id)
                && $0.isDriveUploadEligible
                && !uploadingItemIDs.contains($0.id)
                && !itemsInProgress.contains($0.id)
        }
        guard !reservedItems.isEmpty else { return }

        let reservedIDs = Set(reservedItems.map(\.id))
        uploadingItemIDs.formUnion(reservedIDs)
        for id in reservedIDs {
            uploadProgresses[id] = 0
            itemErrors.removeValue(forKey: id)
        }
        updateDriveActivityState()
        driveUploadError = nil
        driveUploadMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            var uploadedCount = 0
            do {
                for item in reservedItems {
                    try Task.checkCancellation()
                    var uploadErrorToThrow: Error? = nil
                    var isFileNotFound = false

                    do {
                        let payload = try await self.prepareUploadPayload(for: item)
                        let name = payload.name
                        let mimeType = payload.mimeType
                        let data = payload.data

                        let progressHandler: @Sendable (Double) -> Void = { progress in
                            Task { @MainActor in
                                if self.uploadingItemIDs.contains(item.id) {
                                    self.uploadProgresses[item.id] = progress
                                }
                            }
                        }

                        let fileId: String
                        if item.driveState == .local {
                            fileId = try await NotchGoogleDriveService.shared.upload(
                                name: name,
                                mimeType: mimeType,
                                data: data,
                                portalBaseURL: portalBaseURL,
                                onProgress: progressHandler
                            )
                        } else {
                            guard let existingId = item.driveFileID else {
                                throw GoogleDriveError.uploadFailed
                            }
                            fileId = try await NotchGoogleDriveService.shared.updateFile(
                                fileId: existingId,
                                name: name,
                                mimeType: mimeType,
                                data: data,
                                portalBaseURL: portalBaseURL,
                                onProgress: progressHandler
                            )
                        }

                        try Task.checkCancellation()
                        await MainActor.run {
                            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                                let currentItem = self.items[index]
                                let updatedItem = currentItem
                                    .withDriveFileID(fileId)
                                    .withDriveUploadedAt(Date())
                                    .withDriveIsPublic(currentItem.driveIsPublic)
                                self.items[index] = updatedItem
                                self.debouncedPersist()
                            }
                        }
                        uploadedCount += 1
                    } catch {
                        if error is CancellationError {
                            throw error
                        }
                        if let driveError = error as? GoogleDriveError, case .fileNotFound = driveError {
                            isFileNotFound = true
                            await MainActor.run {
                                if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                                    let resetItem = self.items[index]
                                        .withDriveFileID(nil)
                                        .withDriveUploadedAt(nil)
                                        .withDriveIsPublic(false)
                                    self.items[index] = resetItem
                                }
                                self.driveUploadMessage = nil
                                self.driveUploadError = "File đã bị xóa trên Google Drive."
                                self.itemErrors[item.id] = "File đã bị xóa trên Google Drive."
                                self.debouncedPersist()
                            }
                        } else {
                            uploadErrorToThrow = error
                            await MainActor.run {
                                self.itemErrors[item.id] = error.localizedDescription
                            }
                        }
                    }

                    _ = await MainActor.run {
                        self.uploadingItemIDs.remove(item.id)
                        self.uploadProgresses.removeValue(forKey: item.id)
                        self.updateDriveActivityState()
                    }

                    if isFileNotFound {
                        await MainActor.run {
                            self.releaseUploadReservations(reservedIDs)
                        }
                        return
                    }

                    if let err = uploadErrorToThrow {
                        throw err
                    }
                }

                await MainActor.run {
                    self.releaseUploadReservations(reservedIDs)
                    self.driveUploadError = nil
                    if uploadedCount > 0 {
                        self.driveUploadMessage = "Tải lên Google Drive thành công!"
                    } else {
                        self.driveUploadMessage = nil
                    }
                    self.debouncedPersist()
                }

                if uploadedCount > 0 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        if self.driveUploadMessage == "Tải lên Google Drive thành công!" {
                            self.driveUploadMessage = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.releaseUploadReservations(reservedIDs)
                    self.driveUploadMessage = nil
                    if !(error is CancellationError) {
                        self.handleGoogleDriveConnectionLossIfNeeded(error)
                        self.driveUploadError = error.localizedDescription
                    }
                    if uploadedCount > 0 {
                        self.debouncedPersist()
                    }
                }
            }
        }
        for id in reservedIDs {
            driveOperationTasks[id] = task
        }
    }

    public func uploadSelectedItemsToDrive() {
        let allSelected = selectedItems
        guard !allSelected.isEmpty else {
            driveUploadError = "Không có mục nào được chọn để tải lên."
            return
        }

        let itemsToUpload = allSelected.filter { $0.isDriveUploadEligible }
        if itemsToUpload.isEmpty {
            driveUploadMessage = "Tất cả các mục đã chọn đều đã được tải lên trước đó."
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    if self.driveUploadMessage == "Tất cả các mục đã chọn đều đã được tải lên trước đó." {
                        self.driveUploadMessage = nil
                    }
                }
            }
            return
        }

        uploadItemsToDrive(itemsToUpload)
    }

    public func shareItemPublicly(_ item: NotchShelfItem) {
        guard let fileId = item.driveFileID else {
            driveUploadError = "File chưa được tải lên Google Drive."
            return
        }
        guard let portalBaseURL = portalBaseURLProvider?() else {
            driveUploadError = "Không thể lấy cấu hình URL hệ thống."
            return
        }
        guard !uploadingItemIDs.contains(item.id), !itemsInProgress.contains(item.id) else {
            return
        }

        driveUploadError = nil
        driveUploadMessage = "Đang cấu hình chia sẻ công khai..."
        self.itemsInProgress.insert(item.id)
        self.itemErrors.removeValue(forKey: item.id)
        updateDriveActivityState()

        Task {
            do {
                try await NotchGoogleDriveService.shared.makeFilePublic(fileId: fileId, portalBaseURL: portalBaseURL)

                await MainActor.run {
                    let link = "https://drive.google.com/file/d/\(fileId)/view?usp=drivesdk"
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([link as NSString])

                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[index] = self.items[index].withDriveIsPublic(true)
                    }

                    self.itemsInProgress.remove(item.id)
                    self.updateDriveActivityState()
                    self.driveUploadError = nil
                    self.driveUploadMessage = "Đã bật chia sẻ công khai và sao chép link!"
                    self.debouncedPersist()
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    if self.driveUploadMessage == "Đã bật chia sẻ công khai và sao chép link!" {
                        self.driveUploadMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.itemsInProgress.remove(item.id)
                    self.updateDriveActivityState()
                    self.driveUploadMessage = nil
                    self.handleGoogleDriveConnectionLossIfNeeded(error)

                    if let driveError = error as? GoogleDriveError, case .fileNotFound = driveError {
                        if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[index] = self.items[index]
                                .withDriveFileID(nil)
                                .withDriveUploadedAt(nil)
                                .withDriveIsPublic(false)
                        }
                        self.driveUploadError = "File đã bị xóa trên Google Drive."
                        self.itemErrors[item.id] = "File đã bị xóa trên Google Drive."
                        self.debouncedPersist()
                    } else {
                        self.driveUploadError = error.localizedDescription
                        self.itemErrors[item.id] = error.localizedDescription
                    }
                }
            }
        }
    }

    public func shareItemPrivately(_ item: NotchShelfItem) {
        guard let fileId = item.driveFileID else {
            driveUploadError = "File chưa được tải lên Google Drive."
            return
        }
        guard let portalBaseURL = portalBaseURLProvider?() else {
            driveUploadError = "Không thể lấy cấu hình URL hệ thống."
            return
        }
        guard !uploadingItemIDs.contains(item.id), !itemsInProgress.contains(item.id) else {
            return
        }

        driveUploadError = nil
        driveUploadMessage = "Đang tắt chế độ chia sẻ công khai..."
        self.itemsInProgress.insert(item.id)
        self.itemErrors.removeValue(forKey: item.id)
        updateDriveActivityState()

        Task {
            do {
                try await NotchGoogleDriveService.shared.makeFilePrivate(fileId: fileId, portalBaseURL: portalBaseURL)

                await MainActor.run {
                    let link = "https://drive.google.com/file/d/\(fileId)/view?usp=drivesdk"
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([link as NSString])

                    if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[index] = self.items[index].withDriveIsPublic(false)
                    }

                    self.itemsInProgress.remove(item.id)
                    self.updateDriveActivityState()
                    self.driveUploadError = nil
                    self.driveUploadMessage = "Đã tắt chia sẻ công khai và sao chép link!"
                    self.debouncedPersist()
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    if self.driveUploadMessage == "Đã tắt chia sẻ công khai và sao chép link!" {
                        self.driveUploadMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.itemsInProgress.remove(item.id)
                    self.updateDriveActivityState()
                    self.driveUploadMessage = nil
                    self.handleGoogleDriveConnectionLossIfNeeded(error)

                    if let driveError = error as? GoogleDriveError, case .fileNotFound = driveError {
                        if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[index] = self.items[index]
                                .withDriveFileID(nil)
                                .withDriveUploadedAt(nil)
                                .withDriveIsPublic(false)
                        }
                        self.driveUploadError = "File đã bị xóa trên Google Drive."
                        self.itemErrors[item.id] = "File đã bị xóa trên Google Drive."
                        self.debouncedPersist()
                    } else {
                        self.driveUploadError = error.localizedDescription
                        self.itemErrors[item.id] = error.localizedDescription
                    }
                }
            }
        }
    }

    private func updateDriveActivityState() {
        isUploadingToDrive = isCompletingDriveHandoff
            || !uploadingItemIDs.isEmpty
            || !itemsInProgress.isEmpty
    }

    private func handleGoogleDriveConnectionLossIfNeeded(_ error: Error) {
        guard let driveError = error as? GoogleDriveError,
              case .notConnected = driveError else {
            return
        }
        NotchGoogleDriveService.shared.clearCredentials()
        isGoogleDriveConnected = false
    }

    private func releaseUploadReservations(_ itemIDs: Set<UUID>) {
        uploadingItemIDs.subtract(itemIDs)
        for id in itemIDs {
            uploadProgresses.removeValue(forKey: id)
            driveOperationTasks.removeValue(forKey: id)
        }
        updateDriveActivityState()
    }

    private func cancelDriveOperations(for itemIDs: Set<UUID>) {
        for id in itemIDs {
            driveOperationTasks[id]?.cancel()
        }
        releaseUploadReservations(itemIDs)
    }

    private func consumePendingGoogleDriveAuthState(_ callbackState: String?) -> Bool {
        guard let callbackState = callbackState?.trimmingCharacters(in: .whitespacesAndNewlines),
              !callbackState.isEmpty,
              let pendingGoogleDriveAuthState,
              let pendingGoogleDriveAuthStateExpiresAt,
              pendingGoogleDriveAuthStateExpiresAt > Date(),
              callbackState == pendingGoogleDriveAuthState else {
            return false
        }

        clearPendingGoogleDriveAuthState()
        return true
    }

    private func clearPendingGoogleDriveAuthState() {
        pendingGoogleDriveAuthState = nil
        pendingGoogleDriveAuthStateExpiresAt = nil
        pendingGoogleDriveCodeVerifier = nil
    }

    private static func makeGoogleDriveAuthState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }

        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        return "\(UUID().uuidString)-\(UUID().uuidString)"
    }

    private static func googleDriveCodeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func refreshDriveStates(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastRefreshTime) > 3 else {
            return
        }
        lastRefreshTime = now

        refreshTask?.cancel()
        let itemsForTask = items
        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            var results: [UUID: NotchShelfItem.ItemDriveState] = [:]
            for item in itemsForTask {
                if Task.isCancelled { return }
                results[item.id] = item.driveState
            }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cachedDriveStates = results
            }
        }
    }

    nonisolated private func prepareUploadPayload(for item: NotchShelfItem) async throws -> (name: String, mimeType: String, data: Data) {
        switch item.kind {
        case .file(let fileRef):
            let bookmark = Bookmark(data: fileRef.bookmarkData)
            let resolved = bookmark.resolve()
            guard let url = resolved.url else {
                throw GoogleDriveError.cannotResolveBookmark
            }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var zipData: Data?
                var readError: Error?

                coordinator.coordinate(readingItemAt: url, options: .forUploading, error: &coordinationError) { coordinatedURL in
                    do {
                        let attributes = try fm.attributesOfItem(atPath: coordinatedURL.path)
                        if let size = attributes[.size] as? NSNumber,
                           size.intValue > NotchGoogleDriveService.maximumUploadByteCount {
                            readError = GoogleDriveError.fileTooLarge
                            return
                        }
                        zipData = try Data(contentsOf: coordinatedURL)
                    } catch {
                        readError = error
                    }
                }

                if let error = coordinationError {
                    throw error
                }
                if let error = readError {
                    throw error
                }
                guard let finalData = zipData else {
                    throw GoogleDriveError.uploadFailed
                }

                return (url.lastPathComponent + ".zip", "application/zip", finalData)
            } else {
                let attributes = try fm.attributesOfItem(atPath: url.path)
                if let size = attributes[.size] as? NSNumber,
                   size.intValue > NotchGoogleDriveService.maximumUploadByteCount {
                    throw GoogleDriveError.fileTooLarge
                }
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent

                let mimeType: String
                if let type = UTType(filenameExtension: url.pathExtension),
                   let mime = type.preferredMIMEType {
                    mimeType = mime
                } else {
                    mimeType = "application/octet-stream"
                }
                return (name, mimeType, data)
            }

        case .link(let url):
            let urlString = url.absoluteString
            guard let rawData = urlString.data(using: .utf8) else {
                throw GoogleDriveError.uploadFailed
            }
            let safeName = item.displayName.replacingOccurrences(of: "/", with: "-")
            let name = safeName.hasSuffix(".txt") ? safeName : "\(safeName).txt"
            return (name, "text/plain", rawData)

        case .text(let string):
            guard let rawData = string.data(using: .utf8) else {
                throw GoogleDriveError.uploadFailed
            }
            let safeName = item.displayName.replacingOccurrences(of: "/", with: "-")
            let name = safeName.hasSuffix(".txt") ? safeName : "\(safeName).txt"
            return (name, "text/plain", rawData)
        }
    }
}
