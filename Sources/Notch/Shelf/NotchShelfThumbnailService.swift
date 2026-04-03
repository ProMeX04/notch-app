import AppKit
import Foundation
import QuickLookThumbnailing

actor NotchShelfThumbnailService {
    static let shared = NotchShelfThumbnailService()

    private var cache: [String: NSImage] = [:]
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let generator = QLThumbnailGenerator.shared

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.standardizedFileURL.path)_\(Int(size.width))x\(Int(size.height))"

        if let cached = cache[cacheKey] {
            return cached
        }

        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<NSImage?, Never> {
            let thumbnail = await generateThumbnail(for: url, size: size)
            if let thumbnail {
                cache[cacheKey] = thumbnail
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
            representationTypes: .all
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
