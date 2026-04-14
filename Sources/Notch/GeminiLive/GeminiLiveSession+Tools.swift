import Foundation
import NotchTooling

extension GeminiLiveSession {
    private var workspaceCodingTools: GeminiWorkspaceCodingTools {
        GeminiWorkspaceCodingTools(
            workspaceRoot: GeminiLiveStoragePaths.workspaceRoot,
            builtInSkillsDirectory: GeminiLiveStoragePaths.builtInSkillsDirectory
        )
    }

    func sendFunctionResponse(id: String, name: String, result: [String: Any]) {
        let responsePayload = GeminiLiveToolResponsePayloadBuilder.buildToolResponsePayload(
            id: id,
            name: name,
            result: result
        )
        let transportResult = GeminiLiveToolResponsePayloadBuilder.transportResult(
            from: result,
            toolName: name
        )

        sendJSONObject(responsePayload)
        GeminiLiveToolLogging.debug("tool response sent for \(name): \(transportResult)")
    }

    func sanitizedToolResultForCallback(name: String, result: [String: Any]) -> [String: Any] {
        GeminiLiveToolResponsePayloadBuilder.transportResult(from: result, toolName: name)
    }

    func notifyFunctionStarted(name: String, args: [String: Any]) {
        onFunctionStarted?(name, args)
    }

    func notifyFunctionExecuted(name: String, args: [String: Any], result: [String: Any]) {
        onFunctionExecuted?(name, args, sanitizedToolResultForCallback(name: name, result: result))
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
            notifyFunctionExecuted(name: name, args: args, result: result)
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
            notifyFunctionExecuted(name: name, args: args, result: result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        let model = "gemini-2.5-flash-lite"
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            let result: [String: Any] = ["success": false, "error": "Couldn't build Gemini search URL."]
            notifyFunctionExecuted(name: name, args: args, result: result)
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
            notifyFunctionExecuted(name: name, args: args, result: result)
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
                self.notifyFunctionExecuted(name: name, args: args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let data else {
                let result: [String: Any] = ["success": false, "error": "No response from Gemini search."]
                self.notifyFunctionExecuted(name: name, args: args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let result: [String: Any] = ["success": false, "error": "Gemini search returned invalid JSON."]
                self.notifyFunctionExecuted(name: name, args: args, result: result)
                self.sendFunctionResponse(id: id, name: name, result: result)
                return
            }

            if let error = json["error"] as? [String: Any] {
                let message = (error["message"] as? String) ?? (error["status"] as? String) ?? "Unknown Gemini search error."
                let result: [String: Any] = ["success": false, "error": message]
                self.notifyFunctionExecuted(name: name, args: args, result: result)
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
            self.notifyFunctionExecuted(name: name, args: args, result: result)
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

    func executeReadFile(path: String, offset: Int? = nil, limit: Int? = nil) -> [String: Any] {
        workspaceCodingTools.executeReadFile(path: path, offset: offset, limit: limit)
    }

    func executeWriteFile(path: String, content: String) -> [String: Any] {
        workspaceCodingTools.executeWriteFile(path: path, content: content)
    }

    func executeLs(path: String?, limit: Int?) -> [String: Any] {
        workspaceCodingTools.executeLs(path: path, limit: limit)
    }

    func executeFind(pattern: String, path: String?, limit: Int?) -> [String: Any] {
        workspaceCodingTools.executeFind(pattern: pattern, path: path, limit: limit)
    }

    func executeGrep(
        pattern: String,
        path: String?,
        glob: String? = nil,
        ignoreCase: Bool = false,
        literal: Bool = false,
        context: Int = 0,
        limit: Int = 100
    ) -> [String: Any] {
        workspaceCodingTools.executeGrep(
            pattern: pattern,
            path: path,
            glob: glob,
            ignoreCase: ignoreCase,
            literal: literal,
            context: context,
            limit: limit
        )
    }

    func executeEditFile(path: String, edits: [GeminiExactTextEdit]) -> [String: Any] {
        workspaceCodingTools.executeEditFile(path: path, edits: edits)
    }

    func executeExec(command: String, workingDirectory: String?, timeoutSeconds: Double?) async -> [String: Any] {
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

        let process = await runProcess(
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

    private func truncatedToolOutput(_ value: String, limit: Int = 8000) -> String {
        guard value.count > limit else { return value }
        let endIndex = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<endIndex]) + "\n...[truncated]"
    }

    private func resolvedWorkspaceToolPath(_ rawPath: String, directoryHint: Bool? = nil) -> URL? {
        GeminiLiveStoragePaths.prepare(fileManager: .default)
        return GeminiLiveStoragePaths.resolvedWorkspacePath(from: rawPath, directoryHint: directoryHint)
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
