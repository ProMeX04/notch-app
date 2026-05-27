import Foundation
@testable import NotchShelfFeature

enum NotchShelfPersistenceServiceTests {

    // MARK: - Happy path

    static func loadReturnsEmpty_whenFileDoesNotExist() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let service = NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json"))
        try expect(service.load().isEmpty)
    }

    static func loadReturnsEmpty_whenFileCorrupted() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let url = dir.appendingPathComponent("items.json")
        try Data("not valid json".utf8).write(to: url)

        let service = NotchShelfPersistenceService(fileURL: url)
        try expect(service.load().isEmpty)
    }

    static func saveThenLoad_roundTripsTextAndLinkItems() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let service = NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json"))

        let textItem = NotchShelfItem(kind: .text("hello world"))
        let linkItem = NotchShelfItem(kind: .link(URL(string: "https://example.com/path")!))
        service.save([textItem, linkItem])

        let loaded = service.load()
        try expectEqual(loaded.count, 2)
        try expectEqual(loaded[0].id, textItem.id)
        try expectEqual(loaded[1].id, linkItem.id)

        guard case let .text(textValue) = loaded[0].kind else {
            throw ShelfTestError.assertion("expected text item at index 0", file: #filePath, line: #line)
        }
        try expectEqual(textValue, "hello world")

        guard case let .link(linkURL) = loaded[1].kind else {
            throw ShelfTestError.assertion("expected link item at index 1", file: #filePath, line: #line)
        }
        try expectEqual(linkURL.absoluteString, "https://example.com/path")
    }

    static func saveOverwritesPreviousContent() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let service = NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json"))
        service.save([NotchShelfItem(kind: .text("first"))])
        service.save([NotchShelfItem(kind: .text("second"))])

        let loaded = service.load()
        try expectEqual(loaded.count, 1)
        guard case let .text(value) = loaded[0].kind else {
            throw ShelfTestError.assertion("expected text item", file: #filePath, line: #line)
        }
        try expectEqual(value, "second")
    }

    static func saveThenLoad_preservesAddedAt() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let service = NotchShelfPersistenceService(fileURL: dir.appendingPathComponent("items.json"))
        let addedAt = Date(timeIntervalSince1970: 123_456)
        service.save([NotchShelfItem(kind: .text("dated"), addedAt: addedAt)])

        let items = service.load()
        try expectEqual(items.count, 1)
        try expectEqual(items[0].addedAt, addedAt)
    }

    // MARK: - Bug #9: init() overwrites corrupted file with empty array (DATA LOSS)

    /// When the persistence file exists but fails to decode, the view model
    /// currently rewrites it with `[]`, silently destroying the user's shelf.
    /// The SAFE behavior is to preserve the bytes until the user actually
    /// mutates the shelf. EXPECTED TO FAIL on the current implementation.
    @MainActor
    static func bug9_initDoesNotOverwriteCorruptedPersistenceFile() throws {
        let dir = try makeTempDirectory(label: "ShelfPersistence")
        defer { cleanupDirectory(dir) }

        let url = dir.appendingPathComponent("items.json")
        let corrupted = Data("corrupted-payload-v1".utf8)
        try corrupted.write(to: url)

        let persistence = NotchShelfPersistenceService(fileURL: url)
        _ = NotchShelfViewModel(persistenceService: persistence)

        let onDisk = try Data(contentsOf: url)
        try expect(
            onDisk == corrupted,
            "init() must not overwrite a corrupted persistence file before the user touches the shelf"
        )
    }
}
