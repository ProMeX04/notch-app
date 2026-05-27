import Foundation
import AVFoundation
import UniformTypeIdentifiers

public actor NotchShelfMetadataService {
    public static let shared = NotchShelfMetadataService()

    private var cache: [URL: String] = [:]
    private var pendingRequests: [URL: Task<String?, Never>] = [:]

    public func metadata(for url: URL) async -> String? {
        let stdUrl = url.standardizedFileURL
        if let cached = cache[stdUrl] {
            return cached
        }

        if let pending = pendingRequests[stdUrl] {
            return await pending.value
        }

        let task = Task<String?, Never> {
            let info = await fetchMetadata(for: stdUrl)
            guard !Task.isCancelled else {
                return nil
            }
            if let info {
                cache[stdUrl] = info
            }
            pendingRequests[stdUrl] = nil
            return info
        }

        pendingRequests[stdUrl] = task
        return await task.value
    }

    private func fetchMetadata(for url: URL) async -> String? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 1. Check if it's a directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                // Filter out hidden files (like .DS_Store) for a more accurate count
                let visibleContents = contents.filter { !$0.hasPrefix(".") }
                let count = visibleContents.count
                if count == 0 {
                    return "No items"
                } else if count == 1 {
                    return "1 item"
                } else {
                    return "\(count) items"
                }
            }
            return nil
        }

        // 2. Check if it's an audio/video file
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .audio) || type.conforms(to: .movie) {
                let asset = AVURLAsset(url: url)
                do {
                    let duration = try await asset.load(.duration)
                    let seconds = duration.seconds
                    guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else {
                        return nil
                    }
                    let secs = Int(round(seconds))
                    let s = secs % 60
                    let m = (secs / 60) % 60
                    let h = secs / 3600

                    if h > 0 {
                        return String(format: "%d:%02d:%02d", h, m, s)
                    } else {
                        return String(format: "%02d:%02d", m, s)
                    }
                } catch {
                    return nil
                }
            }
        }

        return nil
    }

    public func clearCache() {
        for task in pendingRequests.values {
            task.cancel()
        }
        cache.removeAll()
        pendingRequests.removeAll()
    }
}
