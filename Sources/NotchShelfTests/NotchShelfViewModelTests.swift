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
}
