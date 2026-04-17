import AppKit
import Foundation
import QuickLookThumbnailing

actor NotchShelfThumbnailService {
    static let shared = NotchShelfThumbnailService()

    private var cache: [String: NSImage] = [:]
    private var cacheKeys: [String] = []
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let generator = QLThumbnailGenerator.shared

    /// Maximum number of thumbnails to keep in memory at any time.
    private let maxCacheEntries = 25

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
        cacheKeys = cacheKeys.filter { !$0.hasPrefix(cachePrefix) }
        pendingRequests = pendingRequests.filter { !$0.key.hasPrefix(cachePrefix) }
    }

    func clearCache(for urls: [URL]) {
        for url in urls {
            clearCache(for: url)
        }
    }

    func clearAllCache() {
        cache.removeAll()
        cacheKeys.removeAll()
        pendingRequests.removeAll()
    }

    /// Evicts the oldest entries when the cache exceeds its limit.
    private func insertCacheEntry(_ key: String, image: NSImage) {
        if cache[key] == nil {
            cacheKeys.append(key)
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
