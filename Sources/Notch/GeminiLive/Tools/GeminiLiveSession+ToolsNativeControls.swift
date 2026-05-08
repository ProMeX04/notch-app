@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    // MARK: - Volume (Native)

    func handleVolumeCommand(_ tokens: [String]) -> [String: Any] {
        guard let action = tokens.first else {
            return ["success": false, "error": "Missing action for 'volume'. Use: get, set, mute, unmute."]
        }

        do {
            switch action {
            case "get":
                var response: [String: Any] = [
                    "success": true,
                    "volume": Int((try SystemAudioOutput.currentVolume() * 100).rounded())
                ]
                if let muted = try SystemAudioOutput.isMuted() {
                    response["muted"] = muted
                }
                return response
            case "set":
                guard let levelStr = tokens.dropFirst().first,
                      let rawLevel = Double(levelStr) else {
                    return ["success": false, "error": "Missing or invalid volume level. Usage: volume set <0-100>"]
                }
                let clampedLevel = min(max(rawLevel, 0), 100)
                try SystemAudioOutput.setVolume(clampedLevel / 100)
                let volume = Int((try SystemAudioOutput.currentVolume() * 100).rounded())
                return ["success": true, "volume": volume]
            case "mute":
                guard try SystemAudioOutput.setMuted(true) else {
                    return ["success": false, "error": "Mute is unsupported on the current output device."]
                }
                return ["success": true, "muted": true]
            case "unmute":
                guard try SystemAudioOutput.setMuted(false) else {
                    return ["success": false, "error": "Mute is unsupported on the current output device."]
                }
                return ["success": true, "muted": false]
            default:
                return ["success": false, "error": "Unknown volume action '\(action)'."]
            }
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }

    // MARK: - App Control (Native)

    func handleAppCommand(_ tokens: [String]) async -> [String: Any] {
        guard !tokens.isEmpty else {
            return ["success": false, "error": "Usage: app <open|quit|check> <name>"]
        }
        let action = tokens[0]
        let appName = Array(tokens.dropFirst()).joined(separator: " ")
        guard !appName.isEmpty else {
            return ["success": false, "error": "Missing app name."]
        }

        switch action {
        case "open":
            let result = await runProcess(
                executablePath: "/usr/bin/open",
                arguments: ["-a", appName],
                timeout: 10
            )
            let success = result.terminationStatus == 0
            return [
                "success": success,
                "appName": appName,
                "message": success ? "\(appName) opened." : "Failed to open \(appName)."
            ]
        case "quit":
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appName)
            let matchedApps = runningApps.isEmpty
                ? NSWorkspace.shared.runningApplications.filter { $0.localizedName == appName }
                : runningApps
            guard !matchedApps.isEmpty else {
                return ["success": false, "appName": appName, "isRunning": false, "error": "\(appName) is not running."]
            }
            let success = matchedApps.reduce(false) { $0 || $1.terminate() }
            return [
                "success": success,
                "appName": appName,
                "message": success ? "\(appName) quit." : "Failed to quit \(appName)."
            ]
        case "check":
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: appName).isEmpty ||
                NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
            return [
                "success": true,
                "appName": appName,
                "isRunning": isRunning
            ]
        default:
            return ["success": false, "error": "Unknown app action '\(action)'. Use: open, quit, check."]
        }
    }

    // MARK: - Clipboard (Native)

    private func handleClipboardCommand(_ tokens: [String], workingDirectory: String?) -> [String: Any] {
        guard let action = tokens.first else {
            return ["success": false, "error": "Missing action for 'clipboard'. Use: read, write, copy-file."]
        }
        switch action {
        case "read":
            let pasteboard = NSPasteboard.general
            let text = pasteboard.string(forType: .string) ?? ""
            return ["success": true, "stdout": text]
        case "write":
            let text = Array(tokens.dropFirst()).joined(separator: " ")
            guard !text.isEmpty else {
                return ["success": false, "error": "Missing text. Usage: clipboard write <text>"]
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(text, forType: .string)
            guard didWrite else {
                return ["success": false, "error": "Failed to write text to the clipboard."]
            }
            return ["success": true, "message": "Copied text to clipboard."]
        case "copy-file":
            let rawPaths = Array(tokens.dropFirst()).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard !rawPaths.isEmpty else {
                return ["success": false, "error": "Missing file path. Usage: clipboard copy-file <path...>"]
            }

            var fileURLs: [NSURL] = []
            for rawPath in rawPaths {
                let expandedPath = resolvedClipboardFilePath(rawPath, workingDirectory: workingDirectory)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
                    return ["success": false, "error": "File does not exist: \(rawPath)"]
                }
                let fileURL = URL(fileURLWithPath: expandedPath, isDirectory: isDirectory.boolValue)
                fileURLs.append(fileURL as NSURL)
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects(fileURLs) else {
                return [
                    "success": false,
                    "error": rawPaths.count == 1
                        ? "Failed to copy file reference to the clipboard."
                        : "Failed to copy file references to the clipboard."
                ]
            }
            return [
                "success": true,
                "message": rawPaths.count == 1
                    ? "Copied file reference to clipboard."
                    : "Copied \(rawPaths.count) file references to clipboard."
            ]
        default:
            return ["success": false, "error": "Unknown clipboard action '\(action)'."]
        }
    }

    private func resolvedClipboardFilePath(_ rawPath: String, workingDirectory: String?) -> String {
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return expandedPath
        }

        let baseDirectory = GeminiLiveStoragePaths.resolvedExecWorkingDirectory(from: workingDirectory)
            ?? GeminiLiveStoragePaths.defaultExecWorkingDirectory
        return baseDirectory.appendingPathComponent(expandedPath).path
    }

    func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL

        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("notch-exec-\(UUID().uuidString)", isDirectory: true)
        let stdoutURL = tempDirectoryURL.appendingPathComponent("stdout.log")
        let stderrURL = tempDirectoryURL.appendingPathComponent("stderr.log")

        do {
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            fileManager.createFile(atPath: stdoutURL.path, contents: nil)
            fileManager.createFile(atPath: stderrURL.path, contents: nil)
        } catch {
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: "Couldn't prepare command output capture: \(error.localizedDescription)",
                timedOut: false
            )
        }

        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            try? fileManager.removeItem(at: tempDirectoryURL)
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: "Couldn't open command output capture: \(error.localizedDescription)",
                timedOut: false
            )
        }

        task.standardOutput = stdoutHandle
        task.standardError = stderrHandle

        do {
            try task.run()
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? fileManager.removeItem(at: tempDirectoryURL)
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: error.localizedDescription,
                timedOut: false
            )
        }

        let didTimeOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                task.waitUntilExit()
                return false
            }
            if let timeout {
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    if task.isRunning {
                        task.terminate()
                        return true
                    }
                    return false
                }
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        try? fileManager.removeItem(at: tempDirectoryURL)

        return ProcessResult(
            terminationStatus: task.terminationStatus,
            stdoutText: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderrText: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            runError: nil,
            timedOut: didTimeOut
        )
    }
}
