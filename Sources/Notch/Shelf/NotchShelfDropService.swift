import AppKit
import Foundation
import UniformTypeIdentifiers

actor NotchShelfTemporaryStorage {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(
        fileManager: FileManager = .default,
        directoryURL: URL = NotchShelfPaths.temporaryFilesDirectory
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
    }

    func prepare() {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func writeFile(
        data: Data,
        suggestedName: String?,
        registeredTypeIdentifiers: [String]
    ) throws -> URL {
        prepare()

        let preferredExtension = registeredTypeIdentifiers
            .compactMap { UTType($0)?.preferredFilenameExtension }
            .first

        let sanitizedBaseName = sanitizeBaseName(suggestedName)
        let fileName: String
        if let preferredExtension,
           !sanitizedBaseName.lowercased().hasSuffix(".\(preferredExtension.lowercased())") {
            fileName = "\(sanitizedBaseName).\(preferredExtension)"
        } else {
            fileName = sanitizedBaseName
        }

        let destination = uniqueFileURL(for: fileName)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func removeFile(at url: URL) {
        guard manages(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func uniqueFileURL(for fileName: String) -> URL {
        let initialURL = directoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        return directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    private func sanitizeBaseName(_ suggestedName: String?) -> String {
        let trimmed = suggestedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }

        return UUID().uuidString
    }

    private func manages(_ url: URL) -> Bool {
        let standardizedDirectory = directoryURL.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path
        return standardizedURL.hasPrefix(standardizedDirectory)
    }
}

struct NotchShelfDropService {
    private let temporaryStorage: NotchShelfTemporaryStorage

    init(temporaryStorage: NotchShelfTemporaryStorage = NotchShelfTemporaryStorage()) {
        self.temporaryStorage = temporaryStorage
    }

    func prepare() async {
        await temporaryStorage.prepare()
    }

    func items(from providers: [NSItemProvider]) async -> [NotchShelfItem] {
        await prepare()

        var results: [NotchShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }

    func removeTemporaryFile(at url: URL) async {
        await temporaryStorage.removeFile(at: url)
    }

    func removeTemporaryFiles(at urls: [URL]) async {
        for url in urls {
            await temporaryStorage.removeFile(at: url)
        }
    }

    private func processProvider(_ provider: NSItemProvider) async -> NotchShelfItem? {
        let internalIdentity = await provider.extractShelfIdentity()

        if let fileURL = await provider.extractFileURL() {
            return fileItem(for: fileURL, isTemporary: false, identityOverride: internalIdentity)
        }

        if let url = await provider.extractURL() {
            return url.isFileURL
                ? fileItem(for: url, isTemporary: false, identityOverride: internalIdentity)
                : NotchShelfItem(kind: .link(url), identityOverride: internalIdentity)
        }

        if let fileURL = await provider.extractItem() {
            return fileItem(for: fileURL, isTemporary: false, identityOverride: internalIdentity)
        }

        if let text = await provider.extractText() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return NotchShelfItem(kind: .text(trimmed), identityOverride: internalIdentity)
        }

        guard let data = await provider.loadData() else { return nil }
        return await fallbackItem(from: data, provider: provider, identityOverride: internalIdentity)
    }

    private func fallbackItem(
        from data: Data,
        provider: NSItemProvider,
        identityOverride: String?
    ) async -> NotchShelfItem? {
        if let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            if let url = URL(string: string), url.scheme != nil {
                return url.isFileURL
                    ? fileItem(for: url, isTemporary: false, identityOverride: identityOverride)
                    : NotchShelfItem(kind: .link(url), identityOverride: identityOverride)
            }

            if string.hasPrefix("/") {
                return fileItem(
                    for: URL(fileURLWithPath: string),
                    isTemporary: false,
                    identityOverride: identityOverride
                )
            }

            return NotchShelfItem(kind: .text(string), identityOverride: identityOverride)
        }

        guard let tempURL = try? await temporaryStorage.writeFile(
            data: data,
            suggestedName: provider.suggestedName,
            registeredTypeIdentifiers: provider.registeredTypeIdentifiers
        ) else {
            return nil
        }

        return fileItem(for: tempURL, isTemporary: true, identityOverride: identityOverride)
    }

    private func fileItem(
        for url: URL,
        isTemporary: Bool,
        identityOverride: String? = nil
    ) -> NotchShelfItem? {
        let normalizedURL = normalizeFileURL(url)

        guard let bookmarkData = try? Bookmark(url: normalizedURL).data else {
            return nil
        }

        return NotchShelfItem(
            kind: .file(
                .init(
                    url: normalizedURL,
                    fileIdentity: notchShelfFileIdentity(for: normalizedURL),
                    bookmarkData: bookmarkData,
                    isTemporary: isTemporary
                )
            ),
            identityOverride: identityOverride
        )
    }

    private func normalizeFileURL(_ url: URL) -> URL {
        let filePathURL = (url as NSURL).filePathURL ?? url
        return filePathURL.resolvingSymlinksInPath().standardizedFileURL
    }
}

private extension NSItemProvider {
    func extractItem() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.item.identifier) else { return nil }
        return await loadURL(typeIdentifier: UTType.item.identifier)
    }

    func extractShelfIdentity() async -> String? {
        guard hasItemConformingToTypeIdentifier(NotchShelfItem.internalDragIdentityTypeIdentifier) else {
            return nil
        }

        return await loadText(typeIdentifier: NotchShelfItem.internalDragIdentityTypeIdentifier)
    }

    func extractFileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await loadURL(typeIdentifier: UTType.fileURL.identifier)
    }

    func extractURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        guard let url = await loadURL(typeIdentifier: UTType.url.identifier) else { return nil }
        return url.scheme == nil ? nil : url
    }

    func extractText() async -> String? {
        let identifiers = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        for identifier in identifiers where hasItemConformingToTypeIdentifier(identifier) {
            if let text = await loadText(typeIdentifier: identifier) {
                return text
            }
        }
        return nil
    }

    func loadData() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, _ in
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                    return
                }

                if let data = item as? Data {
                    continuation.resume(returning: data)
                    return
                }

                if let string = item as? String {
                    continuation.resume(returning: string.data(using: .utf8))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    func loadURL(typeIdentifier: String) async -> URL? {
        let parseURL: @Sendable (String) -> URL? = { string in
            if let url = URL(string: string) {
                return url
            }

            if string.hasPrefix("/") {
                return URL(fileURLWithPath: string)
            }

            return nil
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: parseURL(string))
                    return
                }

                if let string = item as? String {
                    continuation.resume(returning: parseURL(string))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                    return
                }

                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: string)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
