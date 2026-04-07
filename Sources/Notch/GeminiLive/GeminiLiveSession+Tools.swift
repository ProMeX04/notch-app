import Foundation

extension GeminiLiveSession {
    func sendFunctionResponse(id: String, name: String, result: [String: Any]) {
        let responsePayload: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": id,
                        "name": name,
                        "response": [
                            "result": result
                        ]
                    ]
                ]
            ]
        ]

        sendJSONObject(responsePayload)
        GeminiLiveToolLogging.debug("tool response sent for \(name): \(result)")
    }

    // MARK: - Web Search

    func executeWebSearchAsync(
        id: String,
        name: String,
        args: [String: Any],
        query: String,
        maxResults: Int
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let result: [String: Any] = ["success": false, "error": "Search query is empty."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        executeWebSearchViaGeminiGrounding(
            id: id,
            name: name,
            args: args,
            query: trimmed,
            maxResults: maxResults
        )
    }

    private func executeWebSearchViaGeminiGrounding(
        id: String,
        name: String,
        args: [String: Any],
        query: String,
        maxResults: Int
    ) {
        guard
            let apiKey = currentConfiguration?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            let result: [String: Any] = ["success": false, "error": "Gemini API key is missing."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        let model = "gemini-2.5-flash-lite"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            let result: [String: Any] = ["success": false, "error": "Couldn't build Gemini search URL."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": query]
                    ]
                ]
            ],
            "tools": [
                ["google_search": [:]]
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            let result: [String: Any] = ["success": false, "error": "Couldn't encode Gemini search payload."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        toolHTTPURLSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                let result: [String: Any] = ["success": false, "error": error.localizedDescription]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let data else {
                let result: [String: Any] = ["success": false, "error": "No response from Gemini search."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let result: [String: Any] = ["success": false, "error": "Gemini search returned invalid JSON."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            if let error = json["error"] as? [String: Any] {
                let message = (error["message"] as? String) ?? (error["status"] as? String) ?? "Unknown Gemini search error."
                let result: [String: Any] = ["success": false, "error": message]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            let candidate = ((json["candidates"] as? [[String: Any]])?.first) ?? [:]
            let content = Self.extractGeminiGroundedContent(candidate)
            let citations = Self.extractGeminiGroundedCitations(candidate, maxResults: maxResults)
            let claims = Self.extractGeminiGroundedClaims(candidate)
            let renderedContent = Self.extractGeminiRenderedContent(candidate)
            let webSearchQueries = Self.extractGeminiSearchQueries(candidate)

            var resultsLines: [String] = []
            resultsLines.append(content.isEmpty ? "No grounded answer returned." : content)
            if !citations.isEmpty {
                resultsLines.append("Sources:")
                resultsLines.append(
                    citations.enumerated().map { index, citation in
                        let title = (citation["title"] as? String) ?? "(no title)"
                        let targetURL = (citation["url"] as? String) ?? ""
                        return "[\(index)] \(title)\n\(targetURL)"
                    }.joined(separator: "\n\n")
                )
            }

            let result: [String: Any] = [
                "success": true,
                "provider": "gemini",
                "model": model,
                "query": query,
                "resultCount": citations.count,
                "summary": content,
                "results": resultsLines.joined(separator: "\n\n"),
                "citations": citations,
                "claims": claims,
                "renderedContent": renderedContent,
                "webSearchQueries": webSearchQueries
            ]
            self.onFunctionExecuted?(name, args, result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }.resume()
    }

    private static func extractGeminiGroundedContent(_ candidate: [String: Any]) -> String {
        let content = candidate["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let texts = parts.compactMap { part -> String? in
            guard let text = part["text"] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return texts.joined(separator: "\n")
    }

    private static func extractGeminiGroundedCitations(
        _ candidate: [String: Any],
        maxResults: Int
    ) -> [[String: Any]] {
        let groundingMetadata = candidate["groundingMetadata"] as? [String: Any]
        let chunks = groundingMetadata?["groundingChunks"] as? [[String: Any]] ?? []
        var citations: [[String: Any]] = []

        for chunk in chunks {
            guard
                let web = chunk["web"] as? [String: Any],
                let url = web["uri"] as? String,
                !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            var citation: [String: Any] = ["url": url]
            if let title = web["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                citation["title"] = title
            }
            citations.append(citation)

            if citations.count >= max(1, min(maxResults, 10)) {
                break
            }
        }

        return citations
    }

    private static func extractGeminiGroundedClaims(_ candidate: [String: Any]) -> [[String: Any]] {
        let groundingMetadata = candidate["groundingMetadata"] as? [String: Any]
        let supports = groundingMetadata?["groundingSupports"] as? [[String: Any]] ?? []

        return supports.compactMap { support in
            guard
                let segment = support["segment"] as? [String: Any],
                let text = segment["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            let indices = (support["groundingChunkIndices"] as? [NSNumber])?.map(\.intValue)
                ?? (support["groundingChunkIndices"] as? [Int])
                ?? []

            return [
                "text": text,
                "groundingChunkIndices": indices
            ]
        }
    }

    private static func extractGeminiRenderedContent(_ candidate: [String: Any]) -> String {
        let groundingMetadata = candidate["groundingMetadata"] as? [String: Any]
        let searchEntryPoint = groundingMetadata?["searchEntryPoint"] as? [String: Any]
        return (searchEntryPoint?["renderedContent"] as? String) ?? ""
    }

    private static func extractGeminiSearchQueries(_ candidate: [String: Any]) -> [String] {
        let groundingMetadata = candidate["groundingMetadata"] as? [String: Any]
        return groundingMetadata?["webSearchQueries"] as? [String] ?? []
    }

    func executeReadFile(path: String) -> [String: Any] {
        guard let fileURL = resolvedReadableToolPath(path) else {
            return readPathErrorResult(path: path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "File does not exist: \(path)"]
        }
        guard !isDirectory.boolValue else {
            return ["success": false, "error": "Path is a directory, not a file: \(path)"]
        }

        do {
            var encoding = String.Encoding.utf8
            let content = try String(contentsOf: fileURL, usedEncoding: &encoding)
            return [
                "success": true,
                "path": GeminiLiveStoragePaths.workspaceRelativePath(for: fileURL),
                "absolutePath": fileURL.path,
                "content": truncatedToolOutput(content, limit: 20_000),
                "encoding": encodingName(encoding)
            ]
        } catch {
            return ["success": false, "error": "Couldn't read file: \(error.localizedDescription)"]
        }
    }

    func executeWriteFile(path: String, content: String) -> [String: Any] {
        guard let fileURL = resolvedWorkspaceToolPath(path) else {
            return workspacePathErrorResult(path: path)
        }

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return [
                "success": true,
                "path": GeminiLiveStoragePaths.workspaceRelativePath(for: fileURL),
                "absolutePath": fileURL.path,
                "bytes": content.lengthOfBytes(using: .utf8),
                "message": "File written."
            ]
        } catch {
            return ["success": false, "error": "Couldn't write file: \(error.localizedDescription)"]
        }
    }

    func executeFindFiles(pattern: String, baseDirectory: String?, maxResults: Int?) -> [String: Any] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return ["success": false, "error": "Pattern is empty."]
        }

        let baseURL: URL
        if let baseDirectory, !baseDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolvedBase = resolvedWorkspaceToolPath(baseDirectory, directoryHint: true) else {
                return workspacePathErrorResult(path: baseDirectory)
            }
            baseURL = resolvedBase
        } else {
            baseURL = GeminiLiveStoragePaths.workspaceRoot
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ["success": false, "error": "Base directory does not exist: \(baseDirectory ?? ".")"]
        }

        let limit = min(max(maxResults ?? 20, 1), 100)
        let normalizedPattern = trimmedPattern.lowercased()
        var matches: [[String: Any]] = []

        if normalizedPattern == "." || GeminiLiveStoragePaths.workspaceRelativePath(for: baseURL).lowercased().contains(normalizedPattern) {
            matches.append([
                "path": GeminiLiveStoragePaths.workspaceRelativePath(for: baseURL),
                "type": "directory"
            ])
        }

        if let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let itemURL as URL in enumerator {
                let relativePath = GeminiLiveStoragePaths.workspaceRelativePath(for: itemURL)
                let candidate = relativePath.lowercased()
                let name = itemURL.lastPathComponent.lowercased()
                guard candidate.contains(normalizedPattern) || name.contains(normalizedPattern) else { continue }

                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                matches.append([
                    "path": relativePath,
                    "type": values?.isDirectory == true ? "directory" : "file"
                ])
                if matches.count >= limit { break }
            }
        }

        return [
            "success": true,
            "pattern": trimmedPattern,
            "baseDirectory": GeminiLiveStoragePaths.workspaceRelativePath(for: baseURL),
            "matches": matches,
            "count": matches.count
        ]
    }

    func executeGrep(pattern: String, path: String?, maxResults: Int?) -> [String: Any] {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return ["success": false, "error": "Pattern is empty."]
        }

        let targetURL: URL
        if let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let resolvedTarget = resolvedWorkspaceToolPath(path) else {
                return workspacePathErrorResult(path: path)
            }
            targetURL = resolvedTarget
        } else {
            targetURL = GeminiLiveStoragePaths.workspaceRoot
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "Path does not exist: \(path ?? ".")"]
        }

        let limit = min(max(maxResults ?? 20, 1), 100)
        let regex = try? NSRegularExpression(pattern: trimmedPattern, options: [.caseInsensitive])
        let fallbackNeedle = regex == nil ? trimmedPattern.lowercased() : nil
        var matches: [[String: Any]] = []

        let searchURLs: [URL]
        if isDirectory.boolValue {
            let enumerator = FileManager.default.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            searchURLs = (enumerator?.allObjects as? [URL] ?? []).filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory != true
            }
        } else {
            searchURLs = [targetURL]
        }

        outerLoop: for fileURL in searchURLs {
            let relativePath = GeminiLiveStoragePaths.workspaceRelativePath(for: fileURL)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            var lineNumber = 0
            content.enumerateLines { line, stop in
                lineNumber += 1
                let hasMatch: Bool
                if let regex {
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    hasMatch = regex.firstMatch(in: line, options: [], range: range) != nil
                } else if let fallbackNeedle {
                    hasMatch = line.lowercased().contains(fallbackNeedle)
                } else {
                    hasMatch = false
                }

                guard hasMatch else { return }
                matches.append([
                    "path": relativePath,
                    "line": lineNumber,
                    "preview": self.truncatedToolOutput(line, limit: 240)
                ])
                if matches.count >= limit {
                    stop = true
                }
            }

            if matches.count >= limit {
                break outerLoop
            }
        }

        return [
            "success": true,
            "pattern": trimmedPattern,
            "path": GeminiLiveStoragePaths.workspaceRelativePath(for: targetURL),
            "matches": matches,
            "count": matches.count,
            "mode": regex == nil ? "plain-text" : "regex"
        ]
    }

    func executeEditFile(path: String, oldText: String, newText: String, replaceAll: Bool) -> [String: Any] {
        guard let fileURL = resolvedWorkspaceToolPath(path) else {
            return workspacePathErrorResult(path: path)
        }

        guard !oldText.isEmpty else {
            return ["success": false, "error": "oldText is empty."]
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return ["success": false, "error": "File does not exist: \(path)"]
        }
        guard !isDirectory.boolValue else {
            return ["success": false, "error": "Path is a directory, not a file: \(path)"]
        }

        do {
            let original = try String(contentsOf: fileURL, encoding: .utf8)
            let matchCount = original.components(separatedBy: oldText).count - 1
            guard matchCount > 0 else {
                return ["success": false, "error": "oldText was not found in the file."]
            }
            if !replaceAll && matchCount > 1 {
                return ["success": false, "error": "oldText appears \(matchCount) times. Retry with replaceAll: true or provide a more specific match."]
            }

            let updated: String
            let replacements: Int
            if replaceAll {
                updated = original.replacingOccurrences(of: oldText, with: newText)
                replacements = matchCount
            } else if let range = original.range(of: oldText) {
                updated = original.replacingCharacters(in: range, with: newText)
                replacements = 1
            } else {
                return ["success": false, "error": "oldText was not found in the file."]
            }

            try updated.write(to: fileURL, atomically: true, encoding: .utf8)
            return [
                "success": true,
                "path": GeminiLiveStoragePaths.workspaceRelativePath(for: fileURL),
                "absolutePath": fileURL.path,
                "replacements": replacements,
                "message": "File edited."
            ]
        } catch {
            return ["success": false, "error": "Couldn't edit file: \(error.localizedDescription)"]
        }
    }

    func executeExec(command: String, workingDirectory: String?, timeoutSeconds: Double?) -> [String: Any] {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return ["success": false, "error": "Command is empty."]
        }

        GeminiLiveStoragePaths.prepare(fileManager: .default)
        let timeout = min(max(timeoutSeconds ?? 15, 1), 30)
        let cwd = GeminiLiveStoragePaths.resolvedExecWorkingDirectory(from: workingDirectory)
        if let cwd {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: cwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return ["success": false, "error": "Working directory does not exist: \(workingDirectory ?? cwd.path)"]
            }
        }

        let process = runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", trimmedCommand],
            currentDirectoryURL: cwd,
            timeout: timeout
        )

        let stdout = truncatedToolOutput(process.stdoutText)
        let stderr = truncatedToolOutput(process.stderrText)
        let exitCode = Int(process.terminationStatus ?? -1)

        if let runError = process.runError {
            var result: [String: Any] = [
                "success": false,
                "command": trimmedCommand,
                "error": "Failed to start command: \(runError)"
            ]
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        if process.timedOut {
            var result: [String: Any] = [
                "success": false,
                "command": trimmedCommand,
                "error": "Command timed out after \(Int(timeout))s.",
                "exitCode": exitCode,
                "stdout": stdout,
                "stderr": stderr
            ]
            if let cwd {
                result["workingDirectory"] = cwd.path
            }
            return result
        }

        var result: [String: Any] = [
            "success": exitCode == 0,
            "command": trimmedCommand,
            "message": exitCode == 0 ? "Command finished successfully." : "Command exited with status \(exitCode).",
            "exitCode": exitCode,
            "stdout": stdout,
            "stderr": stderr
        ]
        if let cwd {
            result["workingDirectory"] = cwd.path
        }
        return result
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
        } catch {
            return ProcessResult(
                terminationStatus: nil,
                stdoutText: "",
                stderrText: "",
                runError: error.localizedDescription,
                timedOut: false
            )
        }

        var didTimeOut = false
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while task.isRunning && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            if task.isRunning {
                didTimeOut = true
                task.terminate()
            }
        }

        task.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            terminationStatus: task.terminationStatus,
            stdoutText: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderrText: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            runError: nil,
            timedOut: didTimeOut
        )
    }

    private func truncatedToolOutput(_ value: String, limit: Int = 8000) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<endIndex]) + "\n...[truncated]"
    }

    private func resolvedWorkspaceToolPath(_ rawPath: String, directoryHint: Bool? = nil) -> URL? {
        GeminiLiveStoragePaths.prepare(fileManager: .default)
        return GeminiLiveStoragePaths.resolvedWorkspacePath(from: rawPath, directoryHint: directoryHint)
    }

    private func resolvedReadableToolPath(_ rawPath: String, directoryHint: Bool? = nil) -> URL? {
        if let workspaceURL = resolvedWorkspaceToolPath(rawPath, directoryHint: directoryHint) {
            return workspaceURL
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { return nil }
        guard let builtInSkillsDirectory = GeminiLiveStoragePaths.builtInSkillsDirectory else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let candidate = URL(fileURLWithPath: expanded, isDirectory: directoryHint ?? false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let builtInRoot = builtInSkillsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = builtInRoot.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8:
            return "utf-8"
        case .utf16:
            return "utf-16"
        case .utf16LittleEndian:
            return "utf-16le"
        case .utf16BigEndian:
            return "utf-16be"
        case .utf32:
            return "utf-32"
        case .ascii:
            return "us-ascii"
        default:
            return "text"
        }
    }

    private func workspacePathErrorResult(path: String) -> [String: Any] {
        [
            "success": false,
            "error": "Path must stay inside ~/.notch/workspace: \(path)"
        ]
    }

    private func readPathErrorResult(path: String) -> [String: Any] {
        [
            "success": false,
            "error": "Read path must stay inside ~/.notch/workspace or match a built-in skill location: \(path)"
        ]
    }
}

private struct ProcessResult {
    let terminationStatus: Int32?
    let stdoutText: String
    let stderrText: String
    let runError: String?
    let timedOut: Bool
}
