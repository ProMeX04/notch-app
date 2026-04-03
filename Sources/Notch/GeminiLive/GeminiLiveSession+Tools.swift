import AppKit
import Foundation

extension GeminiLiveSession {
    func executeDisplayImageAsync(
        id: String,
        name: String,
        args: [String: Any],
        query: String,
        caption: String?,
        orientation: String?,
        apiKeyOverride: String? = nil
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            let result: [String: Any] = ["success": false, "error": "Image query is empty."]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        let resolvedAPIKey = apiKeyOverride ?? currentConfiguration?.pexelsAPIKey
        guard let apiKey = resolvedAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            let result: [String: Any] = ["success": false, "error": prefixedProviderMessage("Pexels", "API key is missing.")]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        guard var components = URLComponents(string: "https://api.pexels.com/v1/search") else {
            let result: [String: Any] = ["success": false, "error": prefixedProviderMessage("Pexels", "Couldn't create the request.")]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        components.queryItems = [
            URLQueryItem(name: "query", value: trimmedQuery),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "orientation", value: normalizedPexelsOrientation(orientation)),
        ]

        guard let url = components.url else {
            let result: [String: Any] = ["success": false, "error": prefixedProviderMessage("Pexels", "Couldn't encode the search query.")]
            onFunctionExecuted?(name, args, result)
            sendFunctionResponse(id: id, name: name, result: result)
            return
        }

        // Acknowledge immediately so Gemini resumes without waiting for the
        // Pexels HTTP round-trip (which would cause it to repeat itself).
        sendFunctionResponse(id: id, name: name, result: ["success": true, "query": trimmedQuery])

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15

        pexelsSession.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }
            let result = self.makeDisplayImageResult(
                query: trimmedQuery,
                caption: caption,
                data: data,
                response: response,
                error: error
            )
            // Only update the overlay — no second toolResponse.
            self.onFunctionExecuted?(name, args, result)
        }.resume()
    }

    private func makeDisplayImageResult(
        query: String,
        caption: String?,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> [String: Any] {
        if let error {
            return ["success": false, "error": prefixedProviderMessage("Pexels", "Request failed: \(error.localizedDescription)")]
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return ["success": false, "error": prefixedProviderMessage("Pexels", "Returned an invalid response.")]
        }

        guard let data else {
            return ["success": false, "error": prefixedProviderMessage("Pexels", "Returned an empty response.")]
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = decodePexelsErrorMessage(from: data)
                ?? "Returned HTTP \(httpResponse.statusCode)."
            return ["success": false, "error": prefixedProviderMessage("Pexels", message)]
        }

        do {
            let payload = try JSONDecoder().decode(PexelsSearchResponse.self, from: data)
            guard let photo = payload.photos.first,
                  let selectedURL = photo.src.large2x ?? photo.src.large ?? photo.src.medium else {
                return ["success": false, "error": prefixedProviderMessage("Pexels", "Found no matching images for \"\(query)\".")]
            }

            let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCaption = (trimmedCaption?.isEmpty == false ? trimmedCaption : nil)
                ?? query.prefix(1).uppercased() + query.dropFirst()
            let request = ImageOverlayRequest(
                query: query,
                imageURL: selectedURL,
                sourceURL: photo.url,
                caption: resolvedCaption,
                photographer: photo.photographer
            )
            onDisplayImageRequest?(request)
            return [
                "success": true,
                "message": "Showing image for \"\(query)\".",
                "imageUrl": request.imageURL.absoluteString
            ]
        } catch {
            return ["success": false, "error": prefixedProviderMessage("Pexels", "Couldn't decode the response: \(error.localizedDescription)")]
        }
    }

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

    private func decodePexelsErrorMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(PexelsErrorResponse.self, from: data),
           !envelope.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envelope.error
        }

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        return nil
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

        pexelsSession.dataTask(with: request) { [weak self] data, response, error in
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

        pexelsSession.dataTask(with: request) { [weak self] data, _, error in
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



    private func normalizedPexelsOrientation(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "portrait":
            return "portrait"
        case "square":
            return "square"
        default:
            return "landscape"
        }
    }

    func executeControlVolume(action: String, level: Int?) -> [String: Any] {
        switch action {
        case "get":
            let result = runAppleScript("output volume of (get volume settings)")
            let isMuted = runAppleScript("output muted of (get volume settings)")
            if let volStr = result, let vol = Int(volStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let muted = isMuted?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                return ["success": true, "volume": vol, "muted": muted, "message": "Volume is \(vol)%, \(muted ? "muted" : "unmuted")."]
            }
            return ["success": false, "message": "Could not read volume."]

        case "set":
            guard let lvl = level else {
                return ["success": false, "message": "Level required for set action."]
            }
            let clamped = max(0, min(100, lvl))
            runAppleScriptVoid("set volume output volume \(clamped)")
            return ["success": true, "message": "Volume set to \(clamped)%."]

        case "mute":
            runAppleScriptVoid("set volume with output muted")
            return ["success": true, "message": "Volume muted."]

        case "unmute":
            runAppleScriptVoid("set volume without output muted")
            return ["success": true, "message": "Volume unmuted."]

        default:
            return ["success": false, "message": "Unknown action: \(action)"]
        }
    }

    @discardableResult
    private func runAppleScript(_ script: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func runAppleScriptVoid(_ script: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
    }

    func executeReadClipboard() -> [String: Any] {
        let pasteboard = NSPasteboard.general
        if let clipboardText = pasteboard.string(forType: .string) {
            return ["success": true, "content": clipboardText]
        } else {
            return ["success": false, "error": "No text content found in clipboard"]
        }
    }

    func executeManageNotes(action: String, title: String?, content: String) -> [String: Any] {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        let escapedContent = content.replacingOccurrences(of: "\"", with: "\\\"")
        
        if action == "add_reminder" {
            let script = "tell application \"Reminders\" to make new reminder with properties {name:\"\(escapedContent)\"}"
            task.arguments = ["osascript", "-e", script]
        } else {
            let noteTitle = (title ?? "New Note").replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"Notes\" to make new note at folder \"Notes\" with properties {name:\"\(noteTitle)\", body:\"\(escapedContent)\"}"
            task.arguments = ["osascript", "-e", script]
        }
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return ["success": true, "message": "Successfully created \(action == "add_reminder" ? "reminder" : "note")"]
            } else {
                return ["success": false, "error": "AppleScript failed. Check app permissions."]
            }
        } catch {
            return ["success": false, "error": "Failed to run AppleScript: \(error.localizedDescription)"]
        }
    }

    func executeControlApp(appName: String, action: String) -> [String: Any] {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return ["success": false, "error": "Application name is missing."]
        }

        guard let appURL = resolvedApplicationURL(named: trimmedName) else {
            return ["success": false, "error": "Could not find application \(trimmedName)."]
        }

        let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier

        switch action {
        case "close":
            guard isApplicationRunning(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: trimmedName) else {
                return ["success": true, "message": "\(trimmedName) is already closed."]
            }

            let targetReference: String
            if let bundleIdentifier {
                targetReference = "id \"\(escapeAppleScriptString(bundleIdentifier))\""
            } else {
                targetReference = "\"\(escapeAppleScriptString(trimmedName))\""
            }

            let command = runProcess(
                executablePath: "/usr/bin/osascript",
                arguments: ["-e", "tell application \(targetReference) to quit"]
            )

            guard command.runError == nil else {
                return ["success": false, "error": "Failed to close application \(trimmedName): \(command.runError!)"]
            }

            guard command.terminationStatus == 0 else {
                let details = command.stderrText.isEmpty ? command.stdoutText : command.stderrText
                let fallback = "AppleScript exited with status \(command.terminationStatus ?? -1)."
                let message = details.isEmpty ? fallback : details
                return ["success": false, "error": "Failed to close application \(trimmedName): \(message)"]
            }

            guard waitForApplicationState(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: trimmedName, isRunning: false, timeout: 3.0) else {
                return ["success": false, "error": "\(trimmedName) received the quit command but is still running."]
            }

            return ["success": true, "message": "Closed \(trimmedName)"]

        case "open":
            if isApplicationRunning(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: trimmedName) {
                return ["success": true, "message": "\(trimmedName) is already open."]
            }

            let command = runProcess(
                executablePath: "/usr/bin/open",
                arguments: [appURL.path]
            )

            guard command.runError == nil else {
                return ["success": false, "error": "Failed to open application \(trimmedName): \(command.runError!)"]
            }

            guard command.terminationStatus == 0 else {
                let details = command.stderrText.isEmpty ? command.stdoutText : command.stderrText
                let fallback = "open exited with status \(command.terminationStatus ?? -1)."
                let message = details.isEmpty ? fallback : details
                return ["success": false, "error": "Failed to open application \(trimmedName): \(message)"]
            }

            guard waitForApplicationState(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: trimmedName, isRunning: true, timeout: 4.0) else {
                return ["success": false, "error": "\(trimmedName) accepted the open command but never appeared as running."]
            }

            return ["success": true, "message": "Opened \(trimmedName)"]

        default:
            return ["success": false, "error": "Unknown app action: \(action)"]
        }
    }

    private func resolvedApplicationURL(named appName: String) -> URL? {
        let workspace = NSWorkspace.shared

        if let fullPath = workspace.fullPath(forApplication: appName) {
            return URL(fileURLWithPath: fullPath)
        }

        if appName.hasSuffix(".app"),
           let fullPath = workspace.fullPath(forApplication: String(appName.dropLast(4))) {
            return URL(fileURLWithPath: fullPath)
        }

        return nil
    }

    private func isApplicationRunning(bundleIdentifier: String?, appURL: URL, appName: String) -> Bool {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }

        let normalizedName = appName.lowercased().replacingOccurrences(of: ".app", with: "")
        return NSWorkspace.shared.runningApplications.contains { app in
            let localizedName = app.localizedName?.lowercased().replacingOccurrences(of: ".app", with: "")
            let bundlePath = app.bundleURL?.resolvingSymlinksInPath().path
            return localizedName == normalizedName || bundlePath == appURL.resolvingSymlinksInPath().path
        }
    }

    private func waitForApplicationState(bundleIdentifier: String?, appURL: URL, appName: String, isRunning: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if isApplicationRunning(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: appName) == isRunning {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return isApplicationRunning(bundleIdentifier: bundleIdentifier, appURL: appURL, appName: appName) == isRunning
    }

    private func escapeAppleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func runProcess(executablePath: String, arguments: [String]) -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments

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
                runError: error.localizedDescription
            )
        }

        task.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            terminationStatus: task.terminationStatus,
            stdoutText: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderrText: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            runError: nil
        )
    }

    /// Detects the macOS default browser and returns its JXA process name + whether it uses Chrome-like API.
    /// Returns (processName, isChromeLike) — falls back to ("Safari", false) if unknown.
    private func defaultBrowserInfo() -> (process: String, isChromeLike: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
        else { return ("Safari", false) }

        // Map bundle IDs → (JXA process name, Chrome-like API)
        let known: [(prefix: String, process: String, chromeLike: Bool)] = [
            ("com.google.chrome",       "Google Chrome",   true),
            ("com.microsoft.edgemac",   "Microsoft Edge",  true),
            ("com.brave.browser",       "Brave Browser",   true),
            ("company.thebrowser.browser", "Arc",          true),  // Arc
            ("org.chromium",            "Chromium",        true),
            ("com.vivaldi",             "Vivaldi",         true),
            ("com.operasoftware",       "Opera",           true),
            ("org.mozilla.firefox",     "Firefox",         false), // Firefox has limited JXA
            ("com.apple.safari",        "Safari",          false),
        ]

        let lower = bundleID.lowercased()
        for entry in known {
            if lower.hasPrefix(entry.prefix) {
                return (entry.process, entry.chromeLike)
            }
        }

        // Fallback: use CFBundleName as process name, assume Chrome-like if not Safari/Firefox
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Safari"
        return (name, true)
    }

    private func duckDuckGoLuckyURL(for query: String) -> URL? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "!ducky \(trimmedQuery)"),
        ]
        return components?.url
    }

    func executeControlBrowser(action: String, url: String?, query: String?) -> [String: Any] {
        let (primaryProcess, primaryIsChrome) = defaultBrowserInfo()

        // Secondary fallback browsers (skip the primary)
        let fallbacks: [(String, Bool)] = [
            ("Google Chrome", true),
            ("Microsoft Edge", true),
            ("Safari", false),
        ].filter { $0.0 != primaryProcess }

        let secondaryProcess = fallbacks.first?.0 ?? "Safari"
        let secondaryIsChrome = fallbacks.first?.1 ?? false

        let safeQuery = (query ?? "").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'")
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        var jxaScript = ""

        if action == "open" {
            let targetURL: String
            if let providedURL = url,
               ["http", "https"].contains(URL(string: providedURL)?.scheme?.lowercased()) {
                targetURL = providedURL
            } else if let query, let luckyURL = duckDuckGoLuckyURL(for: query) {
                targetURL = luckyURL.absoluteString
            } else {
                return ["success": false, "error": "A valid URL or search query is required."]
            }

            // `open` command always uses the default browser — no JXA needed
            let fallbackTask = Process()
            fallbackTask.launchPath = "/usr/bin/env"
            fallbackTask.arguments = ["open", targetURL]
            do {
                try fallbackTask.run()
                let message = url != nil
                    ? "Opened URL in default browser (\(primaryProcess))"
                    : "Opened DuckDuckGo Lucky result in default browser (\(primaryProcess))"
                return ["success": true, "message": message]
            } catch {
                return ["success": false, "error": error.localizedDescription]
            }
        } else if action == "list" {
            func listBlock(process: String, isChrome: Bool) -> String {
                let label = process  // use actual process name as label
                return """
                if (sys.processes.byName("\(process)").exists()) {
                    var app_\(process.replacingOccurrences(of: " ", with: "_")) = Application("\(process)");
                    var wins = app_\(process.replacingOccurrences(of: " ", with: "_")).windows();
                    for (var w=0; w<wins.length; w++) {
                        var tabs = wins[w].tabs();
                        for (var t=0; t<tabs.length; t++) {
                            result += "[\(label)] " + \(isChrome ? "tabs[t].title()" : "tabs[t].name()") + " - " + tabs[t].url() + "\\n";
                        }
                    }
                }
                """
            }
            jxaScript = """
            var result = "";
            var sys = Application("System Events");
            \(listBlock(process: primaryProcess, isChrome: primaryIsChrome))
            \(listBlock(process: secondaryProcess, isChrome: secondaryIsChrome))
            if (result === "") { result = "No open tabs found."; }
            result;
            """
        } else if action == "close" || action == "switch" {
            func searchBlock(process: String, isChrome: Bool, isFirst: Bool) -> String {
                let prefix = isFirst ? "" : "if (!success && "
                let suffix = isFirst ? "" : ")"
                let titleProp = isChrome ? "tabs[t].title()" : "tabs[t].name()"
                let switchAction = isChrome
                    ? "wins[w].activeTabIndex = t + 1; wins[w].index = 1; app.activate();"
                    : "app.windows[0].currentTab = tabs[t]; wins[w].index = 1; app.activate();"
                return """
                \(isFirst ? "" : "if (!success) {")
                if (sys.processes.byName("\(process)").exists()) {
                    var app = Application("\(process)");
                    var wins = app.windows();
                    for (var w=0; w<wins.length; w++) {
                        var tabs = wins[w].tabs();
                        for (var t=0; t<tabs.length; t++) {
                            var title = \(titleProp).toLowerCase();
                            var url = tabs[t].url().toLowerCase();
                            if (title.indexOf(q) > -1 || url.indexOf(q) > -1) {
                                if ("\(action)" === "close") { tabs[t].close(); }
                                else { \(switchAction) }
                                success = true; break;
                            }
                        }
                        if (success) break;
                    }
                }
                \(isFirst ? "" : "}")
                """
            }
            jxaScript = """
            var q = "\(safeQuery)".toLowerCase();
            var success = false;
            var sys = Application("System Events");
            \(searchBlock(process: primaryProcess, isChrome: primaryIsChrome, isFirst: true))
            \(searchBlock(process: secondaryProcess, isChrome: !primaryIsChrome, isFirst: false))
            success ? "Success" : "Tab not found";
            """
        } else if action == "reload" {
            let reloadChrome = """
            if (sys.processes.byName("Google Chrome").exists()) {
                var chrome = Application("Google Chrome");
                if (chrome.frontmost()) { chrome.windows[0].activeTab.reload(); success = true; }
            }
            """
            let reloadSafari = """
            if (!success && sys.processes.byName("Safari").exists()) {
                var safari = Application("Safari");
                if (safari.frontmost() || !success) {
                    safari.doJavaScript("window.location.reload()", { in: safari.windows[0].currentTab() });
                    success = true;
                }
            }
            """
            jxaScript = """
            var success = false;
            var sys = Application("System Events");
            \(primaryIsChrome ? reloadChrome : reloadSafari)
            \(primaryIsChrome ? reloadSafari : reloadChrome)
            success ? "Reloaded" : "No active browser to reload";
            """
        } else if action == "read" {
            let readChrome = """
            if (sys.processes.byName("\(primaryProcess)").exists()) {
                var browser = Application("\(primaryProcess)");
                if (browser.windows.length > 0) {
                    var tab = browser.windows[0].activeTab;
                    success = true;
                    result = tab.execute({javascript: "document.body.innerText.substring(0, 8000)"});
                }
            }
            """
            // For secondary or fallback we can generalize later if needed, but we mostly just check primary Chrome-like or Safari.
            // Let's create proper JS generation for read
            func readBlock(process: String, isChrome: Bool) -> String {
                let jsCall = isChrome
                    ? "tab.execute({javascript: \"document.body.innerText.substring(0, 8000)\"})"
                    : "app.doJavaScript(\"document.body.innerText.substring(0, 8000)\", {in: tab})"
                let actTab = isChrome ? "activeTab" : "currentTab"
                return """
                if (!success && sys.processes.byName("\(process)").exists()) {
                    var app = Application("\(process)");
                    if (app.windows.length > 0) {
                        var tab = app.windows[0].\(actTab);
                        success = true;
                        result = \(jsCall);
                    }
                }
                """
            }
            jxaScript = """
            var success = false;
            var result = "";
            var sys = Application("System Events");
            \(readBlock(process: primaryProcess, isChrome: primaryIsChrome))
            if (!success) {
                // optional secondary browser attempt
                \(readBlock(process: secondaryProcess, isChrome: secondaryIsChrome))
            }
            success ? result : "Error: No active browser window found.";
            """
        } else {
            return ["success": false, "error": "Unknown action"]
        }

        task.arguments = ["-l", "JavaScript", "-e", jxaScript]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if task.terminationStatus == 0 {
                return ["success": true, "message": output]
            } else {
                return ["success": false, "error": output]
            }
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }
}

private struct ProcessResult {
    let terminationStatus: Int32?
    let stdoutText: String
    let stderrText: String
    let runError: String?
}

private struct PexelsSearchResponse: Decodable {
    let photos: [Photo]

    struct Photo: Decodable {
        let url: URL?
        let photographer: String?
        let src: SourceSet
    }

    struct SourceSet: Decodable {
        let medium: URL?
        let large: URL?
        let large2x: URL?
    }
}

private struct PexelsErrorResponse: Decodable {
    let error: String
}

private struct PexelsImageFailure: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
