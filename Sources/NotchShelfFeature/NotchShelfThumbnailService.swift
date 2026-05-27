import AppKit
import Foundation
import QuickLookThumbnailing

public actor NotchShelfThumbnailService {
    public static let shared = NotchShelfThumbnailService()

    // Exposed as internal only for @testable access from NotchShelfTests so
    // we can seed and observe cache state without doing real file I/O.
    internal var cache: [String: NSImage] = [:]
    internal var cacheKeys: [String] = []
    internal var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let generator = QLThumbnailGenerator.shared

    /// Maximum number of thumbnails to keep in memory at any time.
    /// Sized so a typical shelf (≤ a few rows) plus recent off-screen items
    /// stays warm across panel show/hide cycles, avoiding regeneration spikes
    /// every time the user reopens the shelf.
    internal let maxCacheEntries = 128

    static func cacheKey(for url: URL, size: CGSize) -> String {
        "\(url.standardizedFileURL.path)_\(Int(size.width))x\(Int(size.height))"
    }

    public func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = Self.cacheKey(for: url, size: size)

        if let cached = cache[cacheKey] {
            // Bug #D: mark this entry as most-recently-used so the next
            // eviction pass does not sweep frequently-accessed thumbnails.
            moveKeyToMRU(cacheKey)
            return cached
        }

        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }

        // Skip directory thumbnail generation as it can be very slow for large folders
        // Use hasDirectoryPath as a safe, string-based check to avoid security-scope issues
        if url.hasDirectoryPath {
            return nil
        }

        let task = Task<NSImage?, Never> {
            let thumbnail = await generateThumbnail(for: url, size: size)
            if let thumbnail {
                insertCacheEntry(cacheKey, image: thumbnail)
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }

        pendingRequests[cacheKey] = task
        return await task.value
    }

    public func clearCache(for url: URL) {
        // Bug #B: cache keys are of the form "<standardizedPath>_WxH". Using
        // the bare path as a prefix matches unrelated siblings (e.g.
        // clearing "/a/b/file" would also wipe "/a/b/file2_100x100"). Appending
        // "_" pins the match to the full path segment of the requested URL.
        let exactPrefix = url.standardizedFileURL.path + "_"
        cache = cache.filter { !$0.key.hasPrefix(exactPrefix) }
        cacheKeys = cacheKeys.filter { !$0.hasPrefix(exactPrefix) }
        pendingRequests = pendingRequests.filter { !$0.key.hasPrefix(exactPrefix) }
    }

    public func clearCache(for urls: [URL]) {
        for url in urls {
            clearCache(for: url)
        }
    }

    public func clearAllCache() {
        cache.removeAll()
        cacheKeys.removeAll()
        pendingRequests.removeAll()
    }

    /// Evicts the oldest entries when the cache exceeds its limit.
    internal func insertCacheEntry(_ key: String, image: NSImage) {
        if cache[key] == nil {
            cacheKeys.append(key)
        } else {
            // Already present — refresh recency. Without this the key keeps
            // its original LRU position even on re-insertion.
            moveKeyToMRU(key)
        }
        cache[key] = image

        if cacheKeys.count > maxCacheEntries {
            let entriesToRemove = cacheKeys.count / 4
            let keysToRemove = cacheKeys.prefix(entriesToRemove)
            for keyToRemove in keysToRemove {
                cache.removeValue(forKey: keyToRemove)
            }
            cacheKeys.removeFirst(entriesToRemove)
        }
    }

    private func moveKeyToMRU(_ key: String) {
        guard let index = cacheKeys.firstIndex(of: key) else { return }
        if index == cacheKeys.count - 1 { return }
        cacheKeys.remove(at: index)
        cacheKeys.append(key)
    }

    private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        request.iconMode = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            generator.generateBestRepresentation(for: request) { representation, _ in
                if let representation {
                    continuation.resume(returning: NSImage(cgImage: representation.cgImage, size: representation.cgImage.size))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension CGImage {
    var size: NSSize {
        NSSize(width: width, height: height)
    }
}
