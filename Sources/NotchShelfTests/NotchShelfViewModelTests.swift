import AppKit
import Foundation
@testable import NotchShelfCore

@MainActor
enum NotchShelfViewModelTests {

    private static func makeViewModel(dir: URL) -> NotchShelfViewModel {
        let persistence = NotchShelfPersistenceService(
            fileURL: dir.appendingPathComponent("items.json")
        )
        return NotchShelfViewModel(persistenceService: persistence)
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

    static func gdrive_expiredCredentialWithoutRefreshStartsDisconnected() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }
        let service = NotchGoogleDriveService.shared
        service.clearCredentials()
        defer { service.clearCredentials() }

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

    static func gdrive_autoUploadSetting() throws {
        let dir = try makeTempDirectory(label: "ShelfVM")
        defer { cleanupDirectory(dir) }

        // Disable auto-upload
        UserDefaults.standard.set(false, forKey: "notchShelfGoogleDriveAutoUploadEnabled")
        let vm = makeViewModel(dir: dir)

        let a = NotchShelfItem(kind: .text("a"))
        vm.merge([a])
        // Since auto-upload is disabled, it remains local and no upload is triggered
        try expectEqual(vm.items[0].driveState, .local)
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
        let service = NotchGoogleDriveService.shared
        service.clearCredentials()
        defer { service.clearCredentials() }

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
}
