import AppKit
import Foundation

@MainActor
enum ShortcutExecutor {
    enum ExecutionError: LocalizedError {
        case invalidURL(String)
        case appNotFound(String)
        case executionCancelled
        case executionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid URL: \(url)"
            case .appNotFound(let id): return "App not found: \(id)"
            case .executionCancelled: return "Execution cancelled by user"
            case .executionFailed(let msg): return "Execution failed: \(msg)"
            }
        }
    }

    /// Callback for actions that require user approval before execution.
    /// The closure receives the item and must call the completion handler with `true` (approve) or `false` (deny).
    static var onApprovalRequired: (@MainActor (ShortcutItem, @MainActor @Sendable (Bool) -> Void) -> Void)?

    static func execute(_ item: ShortcutItem) async throws {
        if item.action.requiresApproval {
            let approved = await withCheckedContinuation { continuation in
                onApprovalRequired?(item) { approved in
                    continuation.resume(returning: approved)
                }
            }
            guard approved else { throw ExecutionError.executionCancelled }
        }

        switch item.action {
        case .openURL(let urlString):
            guard let url = URL(string: urlString) else {
                throw ExecutionError.invalidURL(urlString)
            }
            NSWorkspace.shared.open(url)

        case .launchApp(let bundleID):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            guard let appURL = app else {
                throw ExecutionError.appNotFound(bundleID)
            }
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        case .appleScript(let source):
            do {
                try await AppleScriptHelper.executeVoid(source)
            } catch {
                throw ExecutionError.executionFailed(error.localizedDescription)
            }

        case .shellCommand(let command):
            do {
                try await executeShellCommand(command)
            } catch {
                throw ExecutionError.executionFailed(error.localizedDescription)
            }

        case .plugin(let type, _):
            // Future: dispatch to registered plugin handlers
            throw ExecutionError.executionFailed("Plugin type '\(type)' is not yet supported")
        }
    }

    // MARK: - Shell

    private static func executeShellCommand(_ command: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error (exit code \(process.terminationStatus))"
                        continuation.resume(
                            throwing: NSError(
                                domain: "ShellCommandError",
                                code: Int(process.terminationStatus),
                                userInfo: [NSLocalizedDescriptionKey: errorMessage]
                            )
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
