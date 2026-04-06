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

        // Use Brave Search API when key is available, otherwise fall back to HTML scraping.
        if let braveAPIKey = currentConfiguration?.braveSearchAPIKey,
           !braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            executeWebSearchViaBraveAPI(
                id: id, name: name, args: args,
                query: trimmed, maxResults: maxResults,
                apiKey: braveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            executeWebSearchViaHTMLScrape(
                id: id, name: name, args: args,
                query: trimmed, maxResults: maxResults
            )
        }
    }

    /// Official Brave Search API — requires a Brave Search API key.
    private func executeWebSearchViaBraveAPI(
        id: String,
        name: String,
        args: [String: Any],
        query: String,
        maxResults: Int,
        apiKey: String
    ) {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "\(min(maxResults, 20))"),
        ]

        guard let url = components.url else {
            let result: [String: Any] = ["success": false, "error": "Couldn't build Brave API URL."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        toolHTTPURLSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                let result: [String: Any] = ["success": false, "error": error.localizedDescription]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let data else {
                let result: [String: Any] = ["success": false, "error": "No response from Brave Search API."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let webSection = json["web"] as? [String: Any],
                  let rawResults = webSection["results"] as? [[String: Any]] else {
                // If the API returned an error body, surface it
                let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                    .flatMap { $0["message"] as? String } ?? "Unexpected API response."
                let result: [String: Any] = ["success": false, "error": errorMsg]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            let lines: [String] = rawResults.prefix(maxResults).compactMap { item in
                guard let title = item["title"] as? String,
                      let url = item["url"] as? String else { return nil }
                let description = item["description"] as? String ?? ""
                var parts = ["• \(title)"]
                if !description.isEmpty { parts.append("  \(description)") }
                parts.append("  \(url)")
                return parts.joined(separator: "\n")
            }

            if lines.isEmpty {
                let result: [String: Any] = ["success": true, "query": query, "results": "No results found."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            let result: [String: Any] = [
                "success": true,
                "query": query,
                "resultCount": lines.count,
                "results": lines.joined(separator: "\n\n"),
            ]
            self.onFunctionExecuted?(name, args, result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }.resume()
    }

    /// Fallback: scrape Brave Search HTML when no API key is configured.
    private func executeWebSearchViaHTMLScrape(
        id: String,
        name: String,
        args: [String: Any],
        query: String,
        maxResults: Int
    ) {
        var components = URLComponents(string: "https://search.brave.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: "web"),
        ]

        guard let url = components.url else {
            let result: [String: Any] = ["success": false, "error": "Couldn't build search URL."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        toolHTTPURLSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                let result: [String: Any] = ["success": false, "error": error.localizedDescription]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let data, let html = String(data: data, encoding: .utf8) else {
                let result: [String: Any] = ["success": false, "error": "No response from search."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            let parsed = Self.parseBraveSearchResults(html, maxResults: min(maxResults, 10))

            if parsed.isEmpty {
                let result: [String: Any] = ["success": true, "query": query, "results": "No results found for \"\(query)\"."]
                self.onFunctionExecuted?(name, args, result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            let lines = parsed.map { item -> String in
                var parts = ["• \(item.title)"]
                if !item.snippet.isEmpty { parts.append("  \(item.snippet)") }
                parts.append("  \(item.url)")
                return parts.joined(separator: "\n")
            }

            let result: [String: Any] = [
                "success": true,
                "query": query,
                "resultCount": parsed.count,
                "results": lines.joined(separator: "\n\n"),
            ]
            self.onFunctionExecuted?(name, args, result)
            self.sendFunctionResponse(id: id, name: name, result: result)
        }.resume()
    }

    private struct SearchResultItem {
        let title: String
        let url: String
        let snippet: String
    }

    /// Parse Brave Search HTML into structured result items.
    private static func parseBraveSearchResults(_ html: String, maxResults: Int) -> [SearchResultItem] {
        // Brave marks each organic result block with data-pos="N"
        let blocks = html.components(separatedBy: "data-pos=\"")
        var results: [SearchResultItem] = []

        for block in blocks.dropFirst() {
            guard results.count < maxResults else { break }

            // Extract the first external https URL (skip brave.com links)
            let urlPattern = #"href="(https://(?!(?:search\.)?brave\.com)[^"]+)""#
            guard let urlRange = block.range(of: urlPattern, options: .regularExpression),
                  let urlCapture = Self.firstCapture(in: String(block[urlRange]), pattern: #"href="([^"]+)""#)
            else { continue }

            // Extract title from heading or strong
            let titleRaw = Self.firstCapture(in: block, pattern: #"<(?:h\d|strong)[^>]*>(.*?)</(?:h\d|strong)>"#)
                ?? Self.firstCapture(in: block, pattern: #"class="[^"]*title[^"]*"[^>]*>(.*?)</\w"#)
                ?? ""
            let title = Self.stripTags(titleRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count > 3 else { continue }

            // Extract snippet
            let snippetRaw = Self.firstCapture(in: block, pattern: #"class="[^"]*snippet[^"]*"[^>]*>(.*?)</p>"#)
                ?? Self.firstCapture(in: block, pattern: #"<p[^>]*>(.*?)</p>"#)
                ?? ""
            let snippet = Self.stripTags(snippetRaw)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(SearchResultItem(title: title, url: urlCapture, snippet: String(snippet.prefix(200))))
        }

        return results
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
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
