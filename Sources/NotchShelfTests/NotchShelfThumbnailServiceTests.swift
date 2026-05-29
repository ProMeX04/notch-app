import AppKit
import Foundation
@testable import NotchShelfFeature

@MainActor
enum NotchShelfThumbnailServiceTests {

    // MARK: - Helpers

    private static func stubImage() -> NSImage {
        NSImage(size: NSSize(width: 1, height: 1))
    }

    private static func seed(_ service: NotchShelfThumbnailService, keys: [String]) async {
        let image = stubImage()
        for key in keys {
            await service.insertCacheEntry(key, image: image)
        }
    }

    private static func key(_ path: String, size: CGSize = CGSize(width: 100, height: 100)) -> String {
        NotchShelfThumbnailService.cacheKey(
            for: URL(fileURLWithPath: path),
            size: size
        )
    }

    // MARK: - Bug #B: clearCache(for:) must not wipe sibling paths

    /// `clearCache(for: /tmp/foo.png)` previously removed every cache entry
    /// whose key started with "/tmp/foo.png", which accidentally swept
    /// `/tmp/foo.png.bak` and `/tmp/foo.png2`. EXPECTED TO FAIL before fix.
    static func bugB_clearCache_onlyClearsExactFilePath() async throws {
        let service = NotchShelfThumbnailService()

        await seed(service, keys: [
            key("/tmp/foo.png"),
            key("/tmp/foo.png.bak"),
            key("/tmp/foo.png2"),
            key("/tmp/foo.png-other"),
            key("/tmp/bar.png"),
        ])

        await service.clearCache(for: URL(fileURLWithPath: "/tmp/foo.png"))

        let remaining = Set(await service.cache.keys)
        let target = key("/tmp/foo.png")
        let bak = key("/tmp/foo.png.bak")
        let two = key("/tmp/foo.png2")
        let other = key("/tmp/foo.png-other")
        let bar = key("/tmp/bar.png")

        try expect(
            !remaining.contains(target),
            "Target path's cache entry must be removed"
        )
        try expect(
            remaining.contains(bak),
            "Sibling path foo.png.bak must not be swept"
        )
        try expect(
            remaining.contains(two),
            "Sibling path foo.png2 must not be swept"
        )
        try expect(
            remaining.contains(other),
            "Sibling path foo.png-other must not be swept"
        )
        try expect(
            remaining.contains(bar),
            "Unrelated path bar.png must not be swept"
        )
    }

    static func clearCache_removesAllSizesForSamePath() async throws {
        let service = NotchShelfThumbnailService()

        await seed(service, keys: [
            key("/tmp/foo.png", size: CGSize(width: 100, height: 100)),
            key("/tmp/foo.png", size: CGSize(width: 200, height: 200)),
            key("/tmp/foo.png", size: CGSize(width: 50, height: 50)),
            key("/tmp/bar.png"),
        ])

        await service.clearCache(for: URL(fileURLWithPath: "/tmp/foo.png"))

        let remaining = Set(await service.cache.keys)
        try expectEqual(remaining, Set([key("/tmp/bar.png")]))
    }

    static func clearCache_multipleURLs() async throws {
        let service = NotchShelfThumbnailService()

        await seed(service, keys: [
            key("/tmp/a.png"),
            key("/tmp/b.png"),
            key("/tmp/c.png"),
        ])

        await service.clearCache(for: [
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/c.png"),
        ])

        let remaining = Set(await service.cache.keys)
        try expectEqual(remaining, Set([key("/tmp/b.png")]))
    }

    // MARK: - Bug #D: LRU eviction must honor read recency

    /// After seeding the cache to its capacity, touching the oldest entry
    /// should move it to the MRU end. The next eviction pass must then
    /// evict the second-oldest entry, not the one we just touched.
    /// EXPECTED TO FAIL before fix.
    static func bugD_cacheHit_updatesLRURecency() async throws {
        let service = NotchShelfThumbnailService()

        let maxEntries = await service.maxCacheEntries
        for i in 0..<maxEntries {
            await seed(service, keys: [key("/tmp/file\(i).png")])
        }

        // Simulate a cache hit on the oldest entry. Because the entry was
        // pre-seeded, the lookup returns on the fast path without doing file
        // I/O; the side-effect we want to observe is that the key is moved
        // to the MRU end of the eviction queue.
        _ = await service.thumbnail(
            for: URL(fileURLWithPath: "/tmp/file0.png"),
            size: CGSize(width: 100, height: 100)
        )

        // Trigger eviction by adding one more entry. `insertCacheEntry`
        // evicts `count / 4` oldest entries once `count > max`.
        await seed(service, keys: [key("/tmp/fileNEW.png")])

        let remaining = Set(await service.cache.keys)
        try expect(
            remaining.contains(key("/tmp/file0.png")),
            "Touched entry must survive the next eviction pass"
        )
        try expect(
            !remaining.contains(key("/tmp/file1.png")),
            "Second-oldest entry (file1) should have been evicted instead of the touched one"
        )
    }

    static func insertCacheEntry_evictsOldestFirst() async throws {
        let service = NotchShelfThumbnailService()

        let maxEntries = await service.maxCacheEntries
        for i in 0..<maxEntries {
            await seed(service, keys: [key("/tmp/file\(i).png")])
        }
        let cacheCount = await service.cache.count
        try expectEqual(cacheCount, maxEntries, "precondition: cache is full")

        await seed(service, keys: [key("/tmp/fileNEW.png")])

        let remaining = Set(await service.cache.keys)
        try expect(
            !remaining.contains(key("/tmp/file0.png")),
            "Oldest entry must be evicted once capacity is exceeded"
        )
        try expect(
            remaining.contains(key("/tmp/fileNEW.png")),
            "Newest inserted entry must be retained"
        )
    }

    static func insertCacheEntry_reinsertingExistingKey_refreshesRecency() async throws {
        let service = NotchShelfThumbnailService()

        await seed(service, keys: [
            key("/tmp/a.png"),
            key("/tmp/b.png"),
            key("/tmp/c.png"),
        ])

        // Re-inserting `a` must move it to the tail of the LRU queue.
        await seed(service, keys: [key("/tmp/a.png")])

        let order = await service.cacheKeys
        try expectEqual(order.last, key("/tmp/a.png"))
        try expectEqual(order.count, 3, "Re-inserting an existing key must not add a duplicate slot")
    }

    static func clearAllCache_empties() async throws {
        let service = NotchShelfThumbnailService()

        await seed(service, keys: [
            key("/tmp/a.png"),
            key("/tmp/b.png"),
        ])

        await service.clearAllCache()

        let cacheEmpty = await service.cache.isEmpty
        let keysEmpty = await service.cacheKeys.isEmpty
        let pendingEmpty = await service.pendingRequests.isEmpty
        try expect(cacheEmpty)
        try expect(keysEmpty)
        try expect(pendingEmpty)
    }
}
