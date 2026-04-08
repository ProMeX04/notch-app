import AppKit
import Foundation
import QuickLookThumbnailing

actor NotchShelfThumbnailService {
    static let shared = NotchShelfThumbnailService()

    private var cache: [String: NSImage] = [:]
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let generator = QLThumbnailGenerator.shared

    /// Maximum number of thumbnails to keep in memory at any time.
    private let maxCacheEntries = 80

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.standardizedFileURL.path)_\(Int(size.width))x\(Int(size.height))"

        if let cached = cache[cacheKey] {
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

    func clearCache(for url: URL) {
        let cachePrefix = url.standardizedFileURL.path
        cache = cache.filter { !$0.key.hasPrefix(cachePrefix) }
        pendingRequests = pendingRequests.filter { !$0.key.hasPrefix(cachePrefix) }
    }

    func clearCache(for urls: [URL]) {
        for url in urls {
            clearCache(for: url)
        }
    }

    /// Evicts the oldest entries when the cache exceeds its limit.
    private func insertCacheEntry(_ key: String, image: NSImage) {
        cache[key] = image

        if cache.count > maxCacheEntries {
            // Simple eviction: remove a quarter of entries.
            // Since Dictionary is unordered this is effectively random, which is fine.
            let entriesToRemove = cache.count / 4
            var removed = 0
            for existingKey in cache.keys {
                guard removed < entriesToRemove else { break }
                cache.removeValue(forKey: existingKey)
                removed += 1
            }
        }
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
