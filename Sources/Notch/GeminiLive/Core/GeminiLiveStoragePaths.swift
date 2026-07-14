import Foundation

/// On-disk layout under ~/.notch used by Talk storage (workspace, user profile, avatars, transcripts).
enum GeminiLiveStoragePaths {
    private static let preparedStorage: Void = {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: stateRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: agentAvatarsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
        } catch {
            // Best-effort setup: stores fall back to empty state if preparation fails.
        }
    }()

    static var stateRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch", isDirectory: true)
    }

    static var workspaceRoot: URL {
        stateRoot.appendingPathComponent("workspace", isDirectory: true)
    }

    static var screenshotsDirectory: URL {
        workspaceRoot.appendingPathComponent("screenshots", isDirectory: true)
    }

    static var agentAvatarsDirectory: URL {
        stateRoot.appendingPathComponent("agent-avatars", isDirectory: true)
    }

    static var transcriptsDirectory: URL {
        stateRoot.appendingPathComponent("transcripts", isDirectory: true)
    }

    static var userFile: URL {
        workspaceRoot.appendingPathComponent("USER.md")
    }

    static var developmentDirectory: URL {
        stateRoot.appendingPathComponent("Development", isDirectory: true)
    }

    static var developmentAPIKeyFile: URL {
        developmentDirectory.appendingPathComponent("gemini-api-key.json")
    }

    static var developmentGeminiLiveClientTokenFile: URL {
        developmentDirectory.appendingPathComponent("gemini-live-client-token.json")
    }

    static var developmentNotchAccountAccessTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-access-token.json")
    }

    static var developmentNotchAccountRefreshTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-refresh-token.json")
    }

    static var developmentBraveSearchAPIKeyFile: URL {
        developmentDirectory.appendingPathComponent("brave-search-api-key.json")
    }

    /// Shared workspace used by tools that need a default working directory.
    static var defaultExecWorkingDirectory: URL {
        workspaceRoot
    }

    static func prepare(fileManager: FileManager = .default) {
        _ = fileManager
        _ = preparedStorage
    }

    static func resolvedExecWorkingDirectory(from workingDirectory: String?) -> URL? {
        let trimmed = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return defaultExecWorkingDirectory
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    static func resolvedWorkspacePath(from path: String?, directoryHint: Bool? = nil) -> URL? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let candidate: URL
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            candidate = URL(fileURLWithPath: expanded, isDirectory: directoryHint ?? false)
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed, isDirectory: directoryHint ?? false)
        }

        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedWorkspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let workspacePath = resolvedWorkspaceRoot.path
        let candidatePath = resolvedCandidate.path
        guard candidatePath == workspacePath || candidatePath.hasPrefix(workspacePath + "/") else {
            return nil
        }
        return resolvedCandidate
    }

    static func workspaceRelativePath(for url: URL) -> String {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let path = resolved.path
        if path == rootPath { return "." }
        guard path.hasPrefix(rootPath + "/") else { return resolved.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

final class UserStore: @unchecked Sendable {
    private let fileURL: URL

    init(fileURL: URL = GeminiLiveStoragePaths.userFile) {
        self.fileURL = fileURL
    }

    func readUserProfile() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func saveUserProfile(_ content: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
