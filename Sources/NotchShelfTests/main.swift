import Foundation

struct TestCase {
    let name: String
    let run: () async throws -> Void
}

@MainActor
func buildTestCases() -> [TestCase] {
    [
        // Persistence
        TestCase(name: "persistence/load returns [] when file does not exist",
                 run: NotchShelfPersistenceServiceTests.loadReturnsEmpty_whenFileDoesNotExist),
        TestCase(name: "persistence/load returns [] when file is corrupted",
                 run: NotchShelfPersistenceServiceTests.loadReturnsEmpty_whenFileCorrupted),
        TestCase(name: "persistence/save then load round-trips text and link items",
                 run: NotchShelfPersistenceServiceTests.saveThenLoad_roundTripsTextAndLinkItems),
        TestCase(name: "persistence/save overwrites previous content",
                 run: NotchShelfPersistenceServiceTests.saveOverwritesPreviousContent),
        TestCase(name: "persistence/Bug #9 init() does not overwrite corrupted persistence file",
                 run: NotchShelfPersistenceServiceTests.bug9_initDoesNotOverwriteCorruptedPersistenceFile),

        // View model
        TestCase(name: "viewmodel/merge inserts new items at top in reversed order",
                 run: NotchShelfViewModelTests.merge_insertsNewItemsAtTopInReversedOrder),
        TestCase(name: "viewmodel/merge dedups by identity key",
                 run: NotchShelfViewModelTests.merge_dedupsByIdentityKey),
        TestCase(name: "viewmodel/merge adds new items on top preserving existing order",
                 run: NotchShelfViewModelTests.merge_addsNewItemsOnTop_preservingExistingOrder),
        TestCase(name: "viewmodel/merge dedups within the same batch",
                 run: NotchShelfViewModelTests.merge_dedupsWithinSameBatch),
        TestCase(name: "viewmodel/merge with all-duplicate batch does not touch selection",
                 run: NotchShelfViewModelTests.merge_allItemsDuplicate_doesNotMutateSelection),
        TestCase(name: "viewmodel/Bug #2 merge selects the visually topmost new item",
                 run: NotchShelfViewModelTests.bug2_mergeSelectsVisuallyTopmostNewItem),
        TestCase(name: "viewmodel/remove deletes item and its selection",
                 run: NotchShelfViewModelTests.remove_deletesItemAndSelection),
        TestCase(name: "viewmodel/removeSelectedItems removes all selected",
                 run: NotchShelfViewModelTests.removeSelectedItems_removesAllSelected),
        TestCase(name: "viewmodel/clear empties items and selection",
                 run: NotchShelfViewModelTests.clear_emptiesItemsAndSelection),
        TestCase(name: "viewmodel/moveItems reorders a single item forward",
                 run: NotchShelfViewModelTests.moveItems_reordersSingleItemForward),
        TestCase(name: "viewmodel/moveItems reorders multiple items preserving relative order",
                 run: NotchShelfViewModelTests.moveItems_reordersMultipleItemsPreservingRelativeOrder),
        TestCase(name: "viewmodel/moveItems is a no-op for identical ordering",
                 run: NotchShelfViewModelTests.moveItems_noOp_forIdenticalOrdering),
        TestCase(name: "viewmodel/Bug #E moveItems does not leak stale IDs into selection",
                 run: NotchShelfViewModelTests.moveItems_staleIDs_doNotLeakIntoSelection),

        // Thumbnail cache
        TestCase(name: "thumbnail/Bug #B clearCache only clears exact file path",
                 run: NotchShelfThumbnailServiceTests.bugB_clearCache_onlyClearsExactFilePath),
        TestCase(name: "thumbnail/clearCache removes all sizes for a given path",
                 run: NotchShelfThumbnailServiceTests.clearCache_removesAllSizesForSamePath),
        TestCase(name: "thumbnail/clearCache accepts multiple URLs",
                 run: NotchShelfThumbnailServiceTests.clearCache_multipleURLs),
        TestCase(name: "thumbnail/Bug #D cache hit updates LRU recency",
                 run: NotchShelfThumbnailServiceTests.bugD_cacheHit_updatesLRURecency),
        TestCase(name: "thumbnail/insertCacheEntry evicts oldest first",
                 run: NotchShelfThumbnailServiceTests.insertCacheEntry_evictsOldestFirst),
        TestCase(name: "thumbnail/insertCacheEntry re-inserting refreshes recency",
                 run: NotchShelfThumbnailServiceTests.insertCacheEntry_reinsertingExistingKey_refreshesRecency),
        TestCase(name: "thumbnail/clearAllCache empties all state",
                 run: NotchShelfThumbnailServiceTests.clearAllCache_empties),
        TestCase(name: "viewmodel/select keeps only IDs that still exist",
                 run: NotchShelfViewModelTests.select_onlyKeepsIDsThatStillExist),
        TestCase(name: "viewmodel/toggleSelection adds and removes",
                 run: NotchShelfViewModelTests.toggleSelection_addsAndRemoves),
        TestCase(name: "viewmodel/gdrive_initialState",
                 run: NotchShelfViewModelTests.gdrive_initialState),
        TestCase(name: "viewmodel/gdrive_callbackError",
                 run: NotchShelfViewModelTests.gdrive_callbackError),
        TestCase(name: "viewmodel/gdrive_rawTokenCallbackIsRejected",
                 run: NotchShelfViewModelTests.gdrive_rawTokenCallbackIsRejected),
        TestCase(name: "viewmodel/gdrive_connectGeneratesAuthState",
                 run: NotchShelfViewModelTests.gdrive_connectGeneratesAuthState),
        TestCase(name: "viewmodel/gdrive_callbackWithoutMatchingStateIsRejected",
                 run: NotchShelfViewModelTests.gdrive_callbackWithoutMatchingStateIsRejected),
        TestCase(name: "viewmodel/gdrive_driveStateCalculation",
                 run: NotchShelfViewModelTests.gdrive_driveStateCalculation),
        TestCase(name: "viewmodel/gdrive_copyDriveLink",
                 run: NotchShelfViewModelTests.gdrive_copyDriveLink),
        TestCase(name: "viewmodel/gdrive_autoUploadSetting",
                 run: NotchShelfViewModelTests.gdrive_autoUploadSetting),
        TestCase(name: "viewmodel/gdrive_fileStateCalculations",
                 run: NotchShelfViewModelTests.gdrive_fileStateCalculations),
        TestCase(name: "viewmodel/persistence_preservesOrphanedDriveFileAfterRestart",
                 run: NotchShelfViewModelTests.persistence_preservesOrphanedDriveFileAfterRestart),
        TestCase(name: "viewmodel/gdrive_cachedDriveStatesUpdates",
                 run: NotchShelfViewModelTests.gdrive_cachedDriveStatesUpdates),
        TestCase(name: "viewmodel/gdrive_rejectsOversizeUploadBeforeNetwork",
                 run: NotchShelfViewModelTests.gdrive_rejectsOversizeUploadBeforeNetwork),
    ]
}

@MainActor
func runAll() async -> Int {
    let tests = buildTestCases()

    var passed = 0
    var failures: [(name: String, error: Error)] = []

    for test in tests {
        do {
            try await test.run()
            print("PASS  \(test.name)")
            passed += 1
        } catch {
            print("FAIL  \(test.name)")
            print("        \(error)")
            failures.append((test.name, error))
        }
    }

    print("")
    print("========== NotchShelfTests summary ==========")
    print("\(passed)/\(tests.count) passed, \(failures.count) failed")
    if !failures.isEmpty {
        print("")
        print("Failing tests:")
        for failure in failures {
            print("  - \(failure.name)")
        }
    }

    return failures.isEmpty ? 0 : 1
}

let exitCode = await runAll()
exit(Int32(exitCode))
