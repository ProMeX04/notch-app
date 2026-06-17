import AppKit
import Foundation
@testable import NotchShelfFeature

private actor MockDriveDeletingService: NotchShelfDriveDeleting {
    enum Mode {
        case succeed
        case fail
    }

    let mode: Mode
    private(set) var deletedIDs: [String] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func deleteFile(fileId: String, portalBaseURL: URL) async throws {
        switch mode {
        case .succeed:
            deletedIDs.append(fileId)
        case .fail:
            throw GoogleDriveError.deleteFailed
        }
    }
}

@MainActor
enum NotchShelfViewModelTests {

    private static func makeViewModel(dir: URL) -> NotchShelfViewModel {
        makeViewModel(dir: dir, preferences: makePreferences())
    }

    private static func makeViewModel(
        dir: URL,
        preferences: NotchShelfPreferences,
        driveDeletingService: any NotchShelfDriveDeleting = NotchGoogleDriveService.shared
    ) -> NotchShelfViewModel {
        NotchShelfViewModel(
            persistenceService: NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json")),
            preferences: preferences,
            driveDeletingService: driveDeletingService
        )
    }

    private static func makePreferences() -> NotchShelfPreferences {
        NotchShelfPreferences(defaults: UserDefaults(suiteName: "dev.notch.shelf.vm.tests.\(UUID().uuidString)")!)
    }

    private static func textItem(_ value: String) -> NotchShelfItem {
        NotchShelfItem(kind: .text(value))
    }

    private static func textValues(_ items: [NotchShelfItem]) -> [String] {
        items.compactMap { item -> String? in
            if case let .text(value) = item.kind { return value }
            return nil
        }
    }

    // MARK: - merge() ordering & dedup

    static func merge_insertsNewItemsAtTopInReversedOrder() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b"); let c = textItem("c")
        vm.merge([a, b, c])

        try expectEqual(textValues(vm.items), ["c", "b", "a"])
    }

    static func merge_dedupsByIdentityKey() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("hello")])
        vm.merge([textItem("hello"), textItem("world")])

        try expectEqual(textValues(vm.items), ["world", "hello"])
    }

    static func merge_addsNewItemsOnTop_preservingExistingOrder() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b")])
        try expectEqual(textValues(vm.items), ["b", "a"], "precondition")

        vm.merge([textItem("c"), textItem("d")])

        // New batch stacks ABOVE previous items, and existing order is kept.
        try expectEqual(textValues(vm.items), ["d", "c", "b", "a"])
        // Selection lands on the visually topmost NEW item (Bug #2 behavior).
        try expectEqual(vm.selectedItemIDs.count, 1)
        try expectEqual(vm.selectedItemIDs, Set([vm.items[0].id]))
    }

    static func merge_dedupsWithinSameBatch() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        // "hello" appears twice in the same drop — only one should land.
        vm.merge([textItem("hello"), textItem("world"), textItem("hello")])

        try expectEqual(textValues(vm.items), ["world", "hello"])
    }

    static func merge_allItemsDuplicate_doesNotMutateSelection() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b")])
        let beforeSelection = vm.selectedItemIDs

        // Dropping only items that duplicate existing identities should be a
        // no-op for the model state (no ordering changes, no selection jump).
        vm.merge([textItem("a"), textItem("b")])

        try expectEqual(textValues(vm.items), ["b", "a"])
        try expectEqual(vm.selectedItemIDs, beforeSelection)
    }

    // MARK: - Bug #2: selection lands on visually bottom new item

    /// After dropping multiple new items, the visually-topmost new item
    /// should be selected. Currently `mergedItems.first` is selected, which
    /// is the BOTTOM of the new group. EXPECTED TO FAIL.
    static func bug2_mergeSelectsVisuallyTopmostNewItem() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b"); let c = textItem("c")
        vm.merge([a, b, c])

        try expectEqual(vm.items.first?.id, c.id, "precondition: c on top")
        try expectEqual(
            vm.selectedItemIDs,
            [c.id],
            "After dropping [a, b, c], the visually-topmost new item (c) should be selected"
        )
    }

    static func duplicateDrop_moveToTop() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let preferences = makePreferences()
        let vm = makeViewModel(dir: dir, preferences: preferences)
        vm.merge([textItem("a"), textItem("b"), textItem("c")])

        vm.merge([textItem("a")])

        try expectEqual(textValues(vm.items), ["a", "c", "b"])
    }

    static func merge_insertsAtTargetIndex() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b")
        vm.merge([a, b])
        try expectEqual(textValues(vm.items), ["b", "a"])

        let c = textItem("c")
        vm.merge([c], atIndex: 1)

        try expectEqual(textValues(vm.items), ["b", "c", "a"])
        try expectEqual(vm.selectedItemIDs, Set([c.id]))
    }

    static func merge_insertsMultipleAtTargetIndex() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b")
        vm.merge([a, b])
        try expectEqual(textValues(vm.items), ["b", "a"])

        let c = textItem("c"); let d = textItem("d")
        vm.merge([c, d], atIndex: 1)

        try expectEqual(textValues(vm.items), ["b", "d", "c", "a"])
        try expectEqual(vm.selectedItemIDs, Set([d.id]))
    }

    static func merge_duplicateDrop_atTargetIndex() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let preferences = makePreferences()
        let vm = makeViewModel(dir: dir, preferences: preferences)
        
        let a = textItem("a"); let b = textItem("b"); let c = textItem("c")
        vm.merge([a, b, c]) // -> [c, b, a]
        try expectEqual(textValues(vm.items), ["c", "b", "a"])

        // Drop duplicate of a at index 1 -> list is [c, a, b]
        vm.merge([textItem("a")], atIndex: 1)
        try expectEqual(textValues(vm.items), ["c", "a", "b"])

        // Drop duplicate of c at index 2 (before b) -> list becomes [a, c, b]
        vm.merge([textItem("c")], atIndex: 2)
        try expectEqual(textValues(vm.items), ["a", "c", "b"])

        // Drop duplicate of c at index 3 (after b / end of list) -> list becomes [a, b, c]
        vm.merge([textItem("c")], atIndex: 3)
        try expectEqual(textValues(vm.items), ["a", "b", "c"])
    }


    static func automaticUploadScopeFiltersOnlyAutomaticCandidates() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let preferences = makePreferences()
        let vm = makeViewModel(dir: dir, preferences: preferences)
        let fileURL = dir.appendingPathComponent("upload.txt")
        try "upload".write(to: fileURL, atomically: true, encoding: .utf8)
        let bookmark = try Bookmark(url: fileURL)
        let file = NotchShelfItem(kind: .file(.init(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )))
        let text = textItem("text")
        let link = NotchShelfItem(kind: .link(URL(string: "https://example.com")!))
        let inserted = [file, text, link]
        vm.merge(inserted)

        preferences.autoUploadScope = .filesOnly
        try expectEqual(vm.automaticUploadCandidates(from: inserted).map(\.id), [file.id])

        preferences.autoUploadScope = .allItems
        try expectEqual(Set(vm.automaticUploadCandidates(from: inserted).map(\.id)), Set(inserted.map(\.id)))
    }

    static func retentionPreviewAndApply() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir, preferences: makePreferences())
        let old = NotchShelfItem(
            kind: .text("old"),
            driveFileID: "drive-old",
            addedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60)
        )
        let recent = NotchShelfItem(kind: .text("recent"), addedAt: Date())
        vm.merge([old, recent])
        let policy = NotchShelfRetentionPolicy(maximumItemCount: .never, expirationInterval: .oneDay)

        let preview = vm.previewRetentionPolicy(policy)
        try expectEqual(preview.itemsToRemoveCount, 1)
        try expectEqual(preview.driveItemsToDeleteCount, 1)

        vm.applyRetentionPolicy(policy)
        try expectEqual(textValues(vm.items), ["recent"])
    }

    static func cleanupDriveDeleteSuccess() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let drive = MockDriveDeletingService(mode: .succeed)
        let vm = makeViewModel(dir: dir, preferences: makePreferences(), driveDeletingService: drive)
        vm.portalBaseURLProvider = { URL(string: "https://example.com")! }
        vm.merge([NotchShelfItem(kind: .text("remote"), driveFileID: "drive-1")])

        vm.clearShelf(deleteDriveFiles: true)
        for _ in 0..<20 where !vm.items.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expect(vm.items.isEmpty)
        let deletedIDs = await drive.deletedIDs
        try expectEqual(deletedIDs, ["drive-1"])
    }

    static func automaticRetentionDeletesDriveWhenEnabled() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let drive = MockDriveDeletingService(mode: .succeed)
        let preferences = makePreferences()
        preferences.deleteDriveFilesDuringAutomaticCleanup = true
        let vm = makeViewModel(dir: dir, preferences: preferences, driveDeletingService: drive)
        vm.portalBaseURLProvider = { URL(string: "https://example.com")! }
        vm.merge([NotchShelfItem(
            kind: .text("expired"),
            driveFileID: "drive-expired",
            addedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60)
        )])

        vm.applyRetentionPolicy(NotchShelfRetentionPolicy(expirationInterval: .oneDay))
        for _ in 0..<20 where !vm.items.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expect(vm.items.isEmpty)
        let deletedIDs = await drive.deletedIDs
        try expectEqual(deletedIDs, ["drive-expired"])
    }

    static func cleanupDriveDeleteFailure() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let drive = MockDriveDeletingService(mode: .fail)
        let vm = makeViewModel(dir: dir, preferences: makePreferences(), driveDeletingService: drive)
        vm.portalBaseURLProvider = { URL(string: "https://example.com")! }
        vm.merge([NotchShelfItem(kind: .text("remote"), driveFileID: "drive-1")])

        vm.clearShelf(deleteDriveFiles: true)
        for _ in 0..<20 where vm.driveUploadError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expectEqual(textValues(vm.items), ["remote"])
        try expectEqual(vm.driveUploadError, "Không thể xóa file trên Google Drive.")
    }

    static func retentionMaximumUsesStableOldestTieBreaker() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir, preferences: makePreferences())
        let sharedDate = Date()
        vm.merge((0..<26).map { NotchShelfItem(kind: .text("\($0)"), addedAt: sharedDate) })

        vm.applyRetentionPolicy(NotchShelfRetentionPolicy(maximumItemCount: .twentyFive))

        try expectEqual(vm.items.count, 25)
        try expect(!textValues(vm.items).contains("0"), "The bottom item is oldest when addedAt values match")
        try expect(textValues(vm.items).contains("25"))
    }

    static func clearShelfLocalOnlyDoesNotDeleteDriveFile() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let drive = MockDriveDeletingService(mode: .succeed)
        let vm = makeViewModel(dir: dir, preferences: makePreferences(), driveDeletingService: drive)
        vm.merge([NotchShelfItem(kind: .text("remote"), driveFileID: "drive-1")])

        vm.clearShelf(deleteDriveFiles: false)

        try expect(vm.items.isEmpty)
        let deletedIDs = await drive.deletedIDs
        try expect(deletedIDs.isEmpty)
    }

    // MARK: - remove / clear

    static func remove_deletesItemAndSelection() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b")
        vm.merge([a, b])

        vm.selectOnly(a)
        vm.remove(a)

        try expectEqual(vm.items.count, 1)
        try expectEqual(vm.items.first?.id, b.id)
        try expect(vm.selectedItemIDs.isEmpty)
    }

    static func removeSelectedItems_removesAllSelected() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a"); let b = textItem("b"); let c = textItem("c")
        vm.merge([a, b, c])

        vm.select(ids: [a.id, c.id])
        vm.removeSelectedItems()

        try expectEqual(vm.items.map(\.id), [b.id])
        try expect(vm.selectedItemIDs.isEmpty)
    }

    static func clear_emptiesItemsAndSelection() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b")])
        vm.selectOnly(vm.items[0])

        vm.clear()

        try expect(vm.items.isEmpty)
        try expect(vm.selectedItemIDs.isEmpty)
    }

    // MARK: - moveItems

    static func moveItems_reordersSingleItemForward() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b"), textItem("c")])
        let snapshot = vm.items
        let head = snapshot[0] // c

        vm.moveItems(with: [head.id], to: snapshot.count)

        try expectEqual(vm.items.map(\.id), [snapshot[1].id, snapshot[2].id, head.id])
    }

    static func moveItems_reordersMultipleItemsPreservingRelativeOrder() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b"), textItem("c"), textItem("d")])
        // vm.items == [d, c, b, a]
        let snapshot = vm.items
        let d = snapshot[0]
        let c = snapshot[1]
        let b = snapshot[2]
        let a = snapshot[3]

        vm.moveItems(with: [d.id, b.id], to: 3)

        try expectEqual(vm.items.map(\.id), [c.id, d.id, b.id, a.id])
        try expectEqual(vm.selectedItemIDs, Set([d.id, b.id]))
    }

    /// Bug #E: callers may pass a UUID for an item that has been deleted
    /// between the initial selection and the drop completion. The input set
    /// must not be trusted as-is — `selectedItemIDs` should only contain IDs
    /// that map to a real item after the reorder.
    static func moveItems_staleIDs_doNotLeakIntoSelection() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b"), textItem("c")])
        // items == [c, b, a]; move `c` to the end together with an unknown id.
        let c = vm.items[0]
        let staleID = UUID()

        vm.moveItems(with: [c.id, staleID], to: 3)

        try expectEqual(vm.selectedItemIDs, Set([c.id]))
        try expect(
            !vm.selectedItemIDs.contains(staleID),
            "Selection must not retain UUIDs that no longer map to an item"
        )
    }

    static func moveItems_noOp_forIdenticalOrdering() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        vm.merge([textItem("a"), textItem("b")])
        let before = vm.items

        vm.moveItems(with: [before[0].id], to: 0)

        try expectEqual(vm.items.map(\.id), before.map(\.id))
    }

    // MARK: - selection API

    static func select_onlyKeepsIDsThatStillExist() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a")
        vm.merge([a])

        vm.select(ids: [a.id, UUID()])

        try expectEqual(vm.selectedItemIDs, Set([a.id]))
    }

    static func toggleSelection_addsAndRemoves() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let vm = makeViewModel(dir: dir)
        let a = textItem("a")
        vm.merge([a])
        // merge() auto-selects newly inserted items, clear before exercising the
        // toggle path so the test starts from a known empty selection.
        vm.clearSelection()

        vm.toggleSelection(a)
        try expectEqual(vm.selectedItemIDs, Set([a.id]))

        vm.toggleSelection(a)
        try expect(vm.selectedItemIDs.isEmpty)
    }

    // MARK: - Google Drive Integration Tests

    static func gdrive_initialState() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)

        vm.disconnectGoogleDrive()
        try expect(!vm.isGoogleDriveConnected)
        try expect(vm.driveUploadMessage == nil)
        try expect(vm.driveUploadError == nil)
    }

    static func gdrive_developmentFileStorage_roundTripsAndDeletes() throws {
        let dir = try makeTempDirectory(label: "GDriveDevelopmentStorage")
        defer { cleanupDirectory(dir) }
        let credentialsURL = dir.appendingPathComponent("credentials.json")

        setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "1", 1)
        setenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE", credentialsURL.path, 1)
        defer {
            NotchGoogleDriveService.shared.clearCredentials()
            setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "0", 1)
            unsetenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE")
        }

        let service = NotchGoogleDriveService.shared
        service.clearCredentials()
        try expect(service.storeCredentials(
            accessToken: "development_access",
            refreshToken: "development_refresh",
            expiresAtDate: Date().addingTimeInterval(3600)
        ))
        service.folderId = "development_folder"

        try expectEqual(service.accessToken, "development_access")
        try expectEqual(service.refreshToken, "development_refresh")
        try expectEqual(service.folderId, "development_folder")
        try expect(FileManager.default.fileExists(atPath: credentialsURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: credentialsURL.path)
        try expectEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))

        service.clearCredentials()
        try expect(!FileManager.default.fileExists(atPath: credentialsURL.path))
    }

    static func gdrive_expiredCredentialWithoutRefreshStartsDisconnected() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let credentialsURL = dir.appendingPathComponent("credentials.json")
        setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "1", 1)
        setenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE", credentialsURL.path, 1)
        defer {
            NotchGoogleDriveService.shared.clearCredentials()
            setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "0", 1)
            unsetenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE")
        }
        let service = NotchGoogleDriveService.shared
        service.clearCredentials()

        try expect(service.storeCredentials(
            accessToken: "expired_access",
            refreshToken: nil,
            expiresAtDate: Date().addingTimeInterval(-60)
        ))

        let vm = makeViewModel(dir: dir)
        try expect(!vm.isGoogleDriveConnected)
    }

    static func gdrive_callbackError() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)
        vm.disconnectGoogleDrive()

        vm.connectGoogleDrive()
        let state = try expectUnwrapped(vm.pendingGoogleDriveAuthState)

        vm.handleGoogleDriveCallback(accessToken: nil, refreshToken: nil, expiresIn: nil, error: "Access Denied", state: state)
        try expect(!vm.isGoogleDriveConnected)
        try expectEqual(vm.driveUploadError, "Kết nối thất bại: Access Denied")
        try expectEqual(vm.pendingGoogleDriveAuthState, nil)
    }

    static func gdrive_rawTokenCallbackIsRejected() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)
        vm.disconnectGoogleDrive()

        vm.connectGoogleDrive()
        let state = try expectUnwrapped(vm.pendingGoogleDriveAuthState)

        vm.handleGoogleDriveCallback(accessToken: "mock_access", refreshToken: "mock_refresh", expiresIn: "3600", error: nil, state: state)
        try expect(!vm.isGoogleDriveConnected)
        try expect(vm.driveUploadError?.contains("handoff an toàn") == true)
        try expectEqual(vm.pendingGoogleDriveAuthState, nil)

        vm.disconnectGoogleDrive()
        try expect(!vm.isGoogleDriveConnected)
        try expect(vm.driveUploadMessage == nil)
        try expect(vm.driveUploadError == nil)
    }

    static func gdrive_connectGeneratesAuthState() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)
        vm.disconnectGoogleDrive()

        var requestedState: String?
        var requestedChallenge: String?
        vm.onConnectGoogleDriveRequested = { state, codeChallenge in
            requestedState = state
            requestedChallenge = codeChallenge
        }

        vm.connectGoogleDrive()
        let state = try expectUnwrapped(requestedState)
        try expect(!state.isEmpty)
        try expectEqual(requestedChallenge?.count, 43)
        try expectEqual(vm.pendingGoogleDriveAuthState, state)
    }

    static func gdrive_callbackWithoutMatchingStateIsRejected() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)
        defer { vm.disconnectGoogleDrive() }
        vm.disconnectGoogleDrive()

        vm.handleGoogleDriveCallback(accessToken: "attacker_access", refreshToken: "attacker_refresh", expiresIn: "3600", error: nil, state: nil)
        try expect(!vm.isGoogleDriveConnected)
        try expectEqual(NotchGoogleDriveService.shared.accessToken, nil)
        try expect(vm.driveUploadError?.contains("Phiên xác thực") == true)

        vm.connectGoogleDrive()
        let state = try expectUnwrapped(vm.pendingGoogleDriveAuthState)
        vm.handleGoogleDriveCallback(accessToken: "attacker_access", refreshToken: "attacker_refresh", expiresIn: "3600", error: nil, state: "wrong-\(state)")
        try expect(!vm.isGoogleDriveConnected)
        try expectEqual(NotchGoogleDriveService.shared.accessToken, nil)
        try expectEqual(vm.pendingGoogleDriveAuthState, state)

        vm.handleGoogleDriveCallback(accessToken: "mock_access", refreshToken: "mock_refresh", expiresIn: "3600", error: nil, state: state)
        try expect(!vm.isGoogleDriveConnected)
        try expectEqual(NotchGoogleDriveService.shared.accessToken, nil)
        try expect(vm.driveUploadError?.contains("handoff an toàn") == true)
    }

    // MARK: - Google Drive Redesign Tests

    static func gdrive_driveStateCalculation() throws {
        // Test text item (immutable, so cannot be modified or orphaned)
        let textItem = NotchShelfItem(kind: .text("test"), driveFileID: nil)
        try expectEqual(textItem.driveState, .local)

        let textSynced = NotchShelfItem(kind: .text("test"), driveFileID: "123", driveIsPublic: false)
        try expectEqual(textSynced.driveState, .synced)

        let textSyncedPublic = NotchShelfItem(kind: .text("test"), driveFileID: "123", driveIsPublic: true)
        try expectEqual(textSyncedPublic.driveState, .syncedPublic)
    }

    static func gdrive_copyDriveLink() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let vm = makeViewModel(dir: dir)
        let item = NotchShelfItem(kind: .text("test"), driveFileID: "123", driveIsPublic: false)
        vm.merge([item])

        vm.copyDriveLink(vm.items[0])

        try expectEqual(vm.driveUploadMessage, "Đã sao chép liên kết Google Drive!")

        // Check pasteboard contents
        let pb = NSPasteboard.general
        let pbString = pb.string(forType: .string)
        try expectEqual(pbString, "https://drive.google.com/file/d/123/view?usp=drivesdk")
    }


    static func gdrive_fileStateCalculations() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let fileURL = dir.appendingPathComponent("state_test.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let bookmark = try Bookmark(url: fileURL)
        let ref = NotchShelfItem.FileReference(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )

        // 1. Local
        let itemLocal = NotchShelfItem(kind: .file(ref), driveFileID: nil)
        try expectEqual(itemLocal.driveState, .local)
        try expect(itemLocal.isDriveUploadEligible)

        // 2. Synced
        let itemSynced = NotchShelfItem(kind: .file(ref), driveFileID: "id123", driveIsPublic: false, driveUploadedAt: Date().addingTimeInterval(60))
        try expectEqual(itemSynced.driveState, .synced)
        try expect(!itemSynced.isDriveUploadEligible)

        // 3. Synced Public
        let itemPublic = NotchShelfItem(kind: .file(ref), driveFileID: "id123", driveIsPublic: true, driveUploadedAt: Date().addingTimeInterval(60))
        try expectEqual(itemPublic.driveState, .syncedPublic)
        try expect(!itemPublic.isDriveUploadEligible)

        // 4. Modified (upload time is in the past)
        let itemModified = NotchShelfItem(kind: .file(ref), driveFileID: "id123", driveIsPublic: false, driveUploadedAt: Date().addingTimeInterval(-60))
        try expectEqual(itemModified.driveState, .modified)
        try expect(itemModified.isDriveUploadEligible)

        // 5. Orphaned (file is missing)
        try FileManager.default.removeItem(at: fileURL)
        let itemOrphaned = NotchShelfItem(kind: .file(ref), driveFileID: "id123", driveIsPublic: false, driveUploadedAt: Date())
        try expectEqual(itemOrphaned.driveState, .orphaned)
        try expect(!itemOrphaned.isDriveUploadEligible)
    }

    static func persistence_preservesOrphanedDriveFileAfterRestart() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        // Create a temp file
        let fileURL = dir.appendingPathComponent("orphaned_test.txt")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        let persistence = NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json"))
        let bookmark = try Bookmark(url: fileURL)
        let ref = NotchShelfItem.FileReference(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )
        let item = NotchShelfItem(
            kind: .file(ref),
            driveFileID: "drive_123",
            driveIsPublic: false,
            driveUploadedAt: Date()
        )

        // Save it
        persistence.save([item])

        // Delete the local file to make it orphaned
        try FileManager.default.removeItem(at: fileURL)

        // Reload from persistence
        let reloadedItems = persistence.load()

        // Verify it was preserved as orphaned instead of being pruned!
        try expectEqual(reloadedItems.count, 1)
        try expectEqual(reloadedItems[0].driveState, .orphaned)
        try expectEqual(reloadedItems[0].driveFileID, "drive_123")
    }

    static func gdrive_cachedDriveStatesUpdates() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let fileURL = dir.appendingPathComponent("cache_test.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let bookmark = try Bookmark(url: fileURL)
        let ref = NotchShelfItem.FileReference(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )

        let item = NotchShelfItem(kind: .file(ref), driveFileID: "drive_123", driveIsPublic: false, driveUploadedAt: Date().addingTimeInterval(60))
        let vm = makeViewModel(dir: dir)
        vm.merge([item])

        // The background verification task updates cachedDriveStates asynchronously.
        // We sleep a bit to let the background Task finish.
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let state = vm.cachedDriveStates[vm.items[0].id]
        try expectEqual(state, .synced)
    }

    static func gdrive_rejectsOversizeUploadBeforeNetwork() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let fileURL = dir.appendingPathComponent("oversize.bin")
        try Data().write(to: fileURL)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(NotchGoogleDriveService.maximumUploadByteCount + 1))
        try handle.close()

        let bookmark = try Bookmark(url: fileURL)
        let reference = NotchShelfItem.FileReference(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )
        let vm = makeViewModel(dir: dir)
        vm.portalBaseURLProvider = { URL(string: "http://127.0.0.1:1")! }
        vm.merge([NotchShelfItem(kind: .file(reference))])

        vm.uploadItemsToDrive(vm.items)
        for _ in 0..<20 where vm.driveUploadError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expectEqual(vm.driveUploadError, "Kích thước file vượt quá giới hạn 100MB.")
        try expect(vm.uploadingItemIDs.isEmpty)
    }

    static func gdrive_shareWithExpiredCredentialAllowsRelink() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let credentialsURL = dir.appendingPathComponent("credentials.json")
        setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "1", 1)
        setenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE", credentialsURL.path, 1)
        defer {
            NotchGoogleDriveService.shared.clearCredentials()
            setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "0", 1)
            unsetenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE")
        }
        let service = NotchGoogleDriveService.shared
        service.clearCredentials()

        try expect(service.storeCredentials(
            accessToken: "initially_valid_access",
            refreshToken: nil,
            expiresAtDate: Date().addingTimeInterval(3600)
        ))

        let vm = makeViewModel(dir: dir)
        try expect(vm.isGoogleDriveConnected)
        vm.portalBaseURLProvider = { URL(string: "http://127.0.0.1:1")! }
        vm.merge([NotchShelfItem(kind: .text("shared"), driveFileID: "drive_123")])

        service.expiresAtDate = Date().addingTimeInterval(-60)
        vm.shareItemPublicly(vm.items[0])
        for _ in 0..<20 where vm.driveUploadError == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expect(!vm.isGoogleDriveConnected)
        try expectEqual(vm.driveUploadError, "Chưa kết nối Google Drive.")
        try expectEqual(service.accessToken, nil)
    }

    static func gdrive_defaultStorage_doesNotUsePlaintextFile() throws {
        let dir = try makeTempDirectory(label: "GDriveDefaultStorage")
        defer { cleanupDirectory(dir) }
        let credentialsURL = dir.appendingPathComponent("credentials.json")

        setenv("NOTCH_DEV_GDRIVE_FILE_STORAGE", "0", 1)
        setenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE", credentialsURL.path, 1)
        defer {
            NotchGoogleDriveService.shared.clearCredentials()
            unsetenv("NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE")
        }

        let service = NotchGoogleDriveService.shared
        service.clearCredentials()
        _ = service.storeCredentials(
            accessToken: "keychain_access",
            refreshToken: "keychain_refresh",
            expiresAtDate: Date().addingTimeInterval(3600)
        )

        try expect(!FileManager.default.fileExists(atPath: credentialsURL.path))
    }

    static func automaticRetentionDoesNotDeleteDriveWhenDisabled() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let drive = MockDriveDeletingService(mode: .succeed)
        let preferences = makePreferences()
        preferences.deleteDriveFilesDuringAutomaticCleanup = false
        let vm = makeViewModel(dir: dir, preferences: preferences, driveDeletingService: drive)
        vm.portalBaseURLProvider = { URL(string: "https://example.com")! }
        vm.merge([NotchShelfItem(
            kind: .text("expired"),
            driveFileID: "drive-expired",
            addedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60)
        )])

        vm.applyRetentionPolicy(NotchShelfRetentionPolicy(expirationInterval: .oneDay))
        for _ in 0..<20 where !vm.items.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        try expect(vm.items.isEmpty)
        let deletedIDs = await drive.deletedIDs
        try expect(deletedIDs.isEmpty)
    }

    static func gdrive_automaticSyncOnModification() async throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        let fileURL = dir.appendingPathComponent("sync_test.txt")
        try "initial content".write(to: fileURL, atomically: true, encoding: .utf8)

        let bookmark = try Bookmark(url: fileURL)
        let ref = NotchShelfItem.FileReference(
            url: fileURL,
            fileIdentity: notchShelfFileIdentity(for: fileURL),
            bookmarkData: bookmark.data,
            isTemporary: false
        )

        let preferences = makePreferences()
        preferences.autoUploadEnabled = true

        let vm = makeViewModel(dir: dir, preferences: preferences)
        vm.portalBaseURLProvider = { URL(string: "https://example.com")! }

        // Setup mock tracker actor
        actor UploadTracker {
            var uploadedId: String? = nil
            var updatedId: String? = nil

            func setUploaded(id: String) {
                uploadedId = id
            }
            func setUpdated(id: String) {
                updatedId = id
            }

            func getUploaded() -> String? { uploadedId }
            func getUpdated() -> String? { updatedId }
        }

        let tracker = UploadTracker()
        vm.driveUploadHandler = { name, mimeType, data, url, progress in
            await tracker.setUploaded(id: "uploaded_drive_file_id")
            return "uploaded_drive_file_id"
        }

        // 1. Connect Google Drive
        vm.isGoogleDriveConnected = true

        // 2. Merge item. Since auto-upload is enabled and Drive is connected, it auto-uploads.
        let item = NotchShelfItem(kind: .file(ref), driveFileID: nil)
        vm.merge([item])

        // Wait for mock upload to complete
        var uploadedId: String? = nil
        for _ in 0..<100 {
            uploadedId = await tracker.getUploaded()
            if uploadedId != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        try expectEqual(uploadedId, "uploaded_drive_file_id")

        // Wait for VM to apply persistent updates
        for _ in 0..<100 where vm.items.first?.driveFileID == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try expectEqual(vm.items.first?.driveFileID, "uploaded_drive_file_id")

        // 3. Setup update mock
        vm.driveUpdateHandler = { existingId, name, mimeType, data, url, progress in
            await tracker.setUpdated(id: "updated_drive_file_id")
            return "updated_drive_file_id"
        }

        // 4. Modify local file on disk. We sleep slightly to ensure modification time is > uploaded time
        try await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
        try "updated content".write(to: fileURL, atomically: true, encoding: .utf8)

        // 5. Force update of states to trigger autoSyncModifiedItemsIfNeeded()
        vm.refreshDriveStates(force: true)

        // Wait for update mock to complete
        var updatedId: String? = nil
        for _ in 0..<100 {
            updatedId = await tracker.getUpdated()
            if updatedId != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try expectEqual(updatedId, "updated_drive_file_id")
    }
}
