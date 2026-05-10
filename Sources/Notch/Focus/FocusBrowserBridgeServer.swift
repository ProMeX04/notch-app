import Combine
import CommonCrypto
import Foundation
import Network
import NotchBridgeParserCore
import NotchFocusCore

final class FocusBrowserBridgeServer: @unchecked Sendable {
    private struct FocusBridgeSnapshot {
        var isRunning = false
        var hasActiveSession = false
        var phase = PomodoroPhase.focus.rawValue
        var remainingSeconds = 0
        var blockedHosts: [String] = []
        var allowedHosts: [String] = []
        var autoOpenUrls: [String] = []

        var focusActive: Bool {
            isRunning && phase == PomodoroPhase.focus.rawValue
        }
    }

    private struct HealthPayload: Codable {
        let ok: Bool
        let app: String
        let bridgeVersion: Int
        let port: UInt16
    }

    private let stateQueue = DispatchQueue(label: "dev.notch.focus-browser-bridge.state")
    private let listenerQueue = DispatchQueue(label: "dev.notch.focus-browser-bridge.listener")
    private let encoder = JSONEncoder()
    private let iso8601Formatter = ISO8601DateFormatter()
    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()
    private var snapshot = FocusBridgeSnapshot()

    // MARK: - Browser Command Bridge

    private struct BrowserCommand: Codable {
        let type: String
        let id: String
        let action: String
        let args: [String: JSONValue]

        init(id: String, action: String, args: [String: JSONValue], type: String = "browser-command") {
            self.type = type
            self.id = id
            self.action = action
            self.args = args
        }
    }

    private enum JSONValue: Codable, @unchecked Sendable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([JSONValue])
        case object([String: JSONValue])
        case null

        var value: Any {
            switch self {
            case .string(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            case .bool(let v): return v
            case .array(let v): return v.map { $0.value }
            case .object(let v): return v.mapValues { $0.value }
            case .null: return NSNull()
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let v = try? container.decode(Bool.self) { self = .bool(v) }
            else if let v = try? container.decode(Int.self) { self = .int(v) }
            else if let v = try? container.decode(Double.self) { self = .double(v) }
            else if let v = try? container.decode(String.self) { self = .string(v) }
            else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
            else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
            else { self = .null }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v): try container.encode(v)
            case .double(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            case .array(let v): try container.encode(v)
            case .object(let v): try container.encode(v)
            case .null: try container.encodeNil()
            }
        }
    }

    private struct BrowserCommandResult: Codable {
        let id: String
        let success: Bool
        let result: [String: JSONValue]?
        let errorMessage: String?
        let contentBlocks: [JSONValue]?
    }

    private let commandQueue = DispatchQueue(label: "dev.notch.browser-bridge.commands")
    private var commandResults: [String: BrowserCommandResult] = [:]
    private var commandWaiters: [String: CheckedContinuation<BrowserCommandResult?, Never>] = [:]
    private var wsConnection: NWConnection?
    private var wsConnected = false
    /// Frame parser — owns the receive buffer, fragment buffer, and all frame state.
    private var wsParser = BrowserBridgeFrameParser()

    /// Returns `true` if the service worker has an active WebSocket connection.
    var isExtensionConnected: Bool {
        commandQueue.sync { wsConnected }
    }

    private let entitlementStore: NotchEntitlementStore
    /// Cached value of `entitlementStore.decision(for: .browserBridge).isAllowed`.
    /// Updated on MainActor via Combine; read from any queue in `broadcastFocusState`.
    private var isBrowserBridgeAllowed = false

    @MainActor
    init(pomodoroViewModel: PomodoroViewModel, blocklistStore: FocusWebsiteBlocklistStore, entitlementStore: NotchEntitlementStore) {
        self.entitlementStore = entitlementStore
        self.isBrowserBridgeAllowed = entitlementStore.decision(for: .browserBridge).isAllowed
        snapshot.isRunning = pomodoroViewModel.isRunning
        snapshot.hasActiveSession = pomodoroViewModel.hasActiveSession
        snapshot.phase = pomodoroViewModel.phase.rawValue
        snapshot.remainingSeconds = pomodoroViewModel.remainingSeconds
        snapshot.blockedHosts = blocklistStore.blockedHosts
        snapshot.allowedHosts = blocklistStore.allowedHosts
        snapshot.autoOpenUrls = blocklistStore.autoOpenUrls

        encoder.outputFormatting = [.sortedKeys]

        Publishers.CombineLatest4(
            pomodoroViewModel.$isRunning,
            pomodoroViewModel.$hasActiveSession,
            pomodoroViewModel.$phase,
            pomodoroViewModel.$remainingSeconds
        )
        .sink { [weak self] isRunning, hasActiveSession, phase, remainingSeconds in
            guard let self else { return }
            self.stateQueue.async {
                self.snapshot.isRunning = isRunning
                self.snapshot.hasActiveSession = hasActiveSession
                self.snapshot.phase = phase.rawValue
                self.snapshot.remainingSeconds = remainingSeconds
                self.broadcastFocusState(snapshot: self.snapshot)
            }
        }
        .store(in: &cancellables)

        blocklistStore.$blockedHosts
            .sink { [weak self] blockedHosts in
                guard let self else { return }
                self.stateQueue.async {
                    self.snapshot.blockedHosts = blockedHosts
                    self.broadcastFocusState(snapshot: self.snapshot)
                }
            }
            .store(in: &cancellables)

        blocklistStore.$allowedHosts
            .sink { [weak self] allowedHosts in
                guard let self else { return }
                self.stateQueue.async {
                    self.snapshot.allowedHosts = allowedHosts
                    self.broadcastFocusState(snapshot: self.snapshot)
                }
            }
            .store(in: &cancellables)

        blocklistStore.$autoOpenUrls
            .sink { [weak self] autoOpenUrls in
                guard let self else { return }
                self.stateQueue.async {
                    self.snapshot.autoOpenUrls = autoOpenUrls
                    self.broadcastFocusState(snapshot: self.snapshot)
                }
            }
            .store(in: &cancellables)

        // Keep isBrowserBridgeAllowed in sync so broadcastFocusState can read it without @MainActor.
        entitlementStore.$snapshot
            .map { [weak self] _ in
                self?.entitlementStore.decision(for: .browserBridge).isAllowed ?? false
            }
            .removeDuplicates()
            .sink { [weak self] allowed in
                self?.isBrowserBridgeAllowed = allowed
            }
            .store(in: &cancellables)
    }

    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: FocusWebsiteBlocklistStore.bridgePort) else {
            NotchLog.app.error("Invalid focus browser bridge port: \(FocusWebsiteBlocklistStore.bridgePort)")
            return
        }

        let parameters = NWParameters(tls: nil, tcp: .init())
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: port)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    NotchLog.app.info("Focus browser bridge ready on 127.0.0.1:\(FocusWebsiteBlocklistStore.bridgePort)")
                case let .failed(error):
                    NotchLog.app.error("Focus browser bridge failed: \(error.localizedDescription)")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            NotchLog.app.error("Couldn't start focus browser bridge: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        commandQueue.sync {
            wsConnection?.cancel()
            wsConnection = nil
            wsConnected = false
        }
        cancellables.removeAll()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: listenerQueue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                NotchLog.app.error("Focus browser bridge receive failed: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var combined = accumulated
            if let data {
                combined.append(data)
            }

            if combined.count > 64 * 1024 {
                self.sendPlainTextResponse(status: "413 Payload Too Large", body: "Request too large.", to: connection)
                return
            }

            if self.hasCompleteHeader(in: combined) || isComplete {
                self.respond(to: combined, connection: connection)
                return
            }

            self.receiveRequest(on: connection, accumulated: combined)
        }
    }

    private func hasCompleteHeader(in data: Data) -> Bool {
        data.range(of: Data("\r\n\r\n".utf8)) != nil
    }

    private func respond(to data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            sendPlainTextResponse(status: "400 Bad Request", body: "Malformed request.", to: connection)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendPlainTextResponse(status: "400 Bad Request", body: "Malformed request line.", to: connection)
            return
        }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let path = URLComponents(string: "http://localhost\(target)")?.path ?? target

        let isUpgrade = request.range(of: "Upgrade: websocket", options: .caseInsensitive) != nil
        if isUpgrade && method == "GET" && (path == "/v1/ws" || path == "/ws") {
            handleWebSocketUpgrade(request: request, connection: connection)
            return
        }

        switch (method, path) {
        case ("OPTIONS", _):
            sendResponse(status: "204 No Content", body: Data(), contentType: "application/json", to: connection)
        case ("GET", "/health"), ("GET", "/v1/health"):
            let payload = HealthPayload(
                ok: true,
                app: "Notch",
                bridgeVersion: Self.bridgeVersion,
                port: FocusWebsiteBlocklistStore.bridgePort
            )
            sendJSONResponse(payload, to: connection)
        default:
            sendPlainTextResponse(status: "404 Not Found", body: "Not found.", to: connection)
        }
    }

    private func sendJSONResponse<T: Encodable>(_ payload: T, to connection: NWConnection) {
        guard let body = try? encoder.encode(payload) else {
            sendPlainTextResponse(status: "500 Internal Server Error", body: "Encode failed.", to: connection)
            return
        }

        sendResponse(status: "200 OK", body: body, contentType: "application/json", to: connection)
    }

    private func sendPlainTextResponse(status: String, body: String, to connection: NWConnection) {
        sendResponse(status: status, body: Data(body.utf8), contentType: "text/plain; charset=utf-8", to: connection)
    }

    private func sendResponse(status: String, body: Data, contentType: String, to connection: NWConnection) {
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Focus State WebSocket Broadcast

    /// Push the current focus state to the connected extension over WebSocket.
    /// Safe to call from any queue.
    private func broadcastFocusState(snapshot: FocusBridgeSnapshot) {
        let isAllowed = isBrowserBridgeAllowed

        let dict: [String: Any] = [
            "type": "focus-state",
            "app": "Notch",
            "bridgeVersion": Self.bridgeVersion,
            "updatedAt": iso8601Formatter.string(from: .now),
            "focusActive": isAllowed ? snapshot.focusActive : false,
            "isRunning": isAllowed ? snapshot.isRunning : false,
            "hasActiveSession": isAllowed ? snapshot.hasActiveSession : false,
            "phase": isAllowed ? snapshot.phase : PomodoroPhase.focus.rawValue,
            "remainingSeconds": isAllowed ? snapshot.remainingSeconds : 0,
            "blockedHosts": isAllowed ? snapshot.blockedHosts : [] as [String],
            "allowedHosts": isAllowed ? snapshot.allowedHosts : [] as [String],
            "autoOpenUrls": isAllowed ? snapshot.autoOpenUrls : [] as [String],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else { return }

        let (connection, connected): (NWConnection?, Bool) = commandQueue.sync { (wsConnection, wsConnected) }
        guard let connection, connected else { return }
        sendWebSocketFrame(opcode: 0x01, payload: data, to: connection)
    }

    // MARK: - Browser Command Public API

    /// Enqueue a browser command. If the extension has an active WebSocket connection, push it immediately.
    /// Returns the result dictionary, or nil if the extension doesn't respond within the timeout.
    func enqueueBrowserCommand(action: String, args: [String: Any], timeout: TimeInterval = 5) async -> [String: Any]? {
        let id = UUID().uuidString
        let jsonArgs = args.mapValues { value -> JSONValue in
            switch value {
            case let v as String: return .string(v)
            case let v as Int: return .int(v)
            case let v as Bool: return .bool(v)
            default: return .string(String(describing: value))
            }
        }
        let command = BrowserCommand(id: id, action: action, args: jsonArgs)

        let (connection, connected) = commandQueue.sync { (wsConnection, wsConnected) }

        NotchLog.app.info("enqueueBrowserCommand: action=\(action) id=\(id) wsConnected=\(connected) hasConnection=\(connection != nil)")

        guard connected, let connection, let data = try? encoder.encode(command) else {
            NotchLog.app.info("enqueueBrowserCommand: NO WebSocket connection")
            return nil
        }

        // Wait for the extension to post a result.
        let result: BrowserCommandResult? = await withCheckedContinuation { continuation in
            commandQueue.sync {
                commandWaiters[id] = continuation
            }

            sendWebSocketFrame(opcode: 0x01, payload: data, to: connection)
            NotchLog.app.info("enqueueBrowserCommand: sent \(data.count) bytes over WebSocket")

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.commandQueue.sync {
                    if let waiter = self.commandWaiters.removeValue(forKey: id) {
                        NotchLog.app.info("Browser command \(action) timed out after \(timeout)s")
                        waiter.resume(returning: nil)
                    }
                }
            }
        }

        commandQueue.sync {
            commandWaiters.removeValue(forKey: id)
            commandResults.removeValue(forKey: id)
        }

        guard let result else { return nil }

        var dict: [String: Any] = [:]
        for (key, val) in result.result ?? [:] { dict[key] = val.value }

        // Pull contentBlocks from either the top-level result or the inline `result` payload
        // (the extension currently nests them inside `result.contentBlocks`).
        var contentBlocks: [Any] = []
        if let outer = result.contentBlocks?.compactMap({ $0.value }) {
            contentBlocks.append(contentsOf: outer)
        }
        if let nested = dict["contentBlocks"] as? [Any] {
            contentBlocks.append(contentsOf: nested)
            dict.removeValue(forKey: "contentBlocks")
        }

        if !contentBlocks.isEmpty {
            let savedPaths = Self.persistScreenshotBlocks(contentBlocks, action: action)
            if !savedPaths.isEmpty {
                dict["screenshotPaths"] = savedPaths
                dict["screenshotPath"] = savedPaths.first
                if let savedNote = Self.makeSavedScreenshotNote(savedPaths) {
                    contentBlocks.append(savedNote)
                }
            }
            dict["contentBlocks"] = contentBlocks
        }

        if let errorMessage = result.errorMessage { dict["errorMessage"] = errorMessage }
        dict["success"] = result.success
        return dict
    }

    // MARK: - Screenshot persistence

    /// Decode any image content blocks returned from the extension and save them to
    /// `~/.notch/workspace/screenshots/`. Returns the absolute paths of saved files,
    /// in the same order they appeared in the response.
    private static func persistScreenshotBlocks(_ blocks: [Any], action: String) -> [String] {
        let directory = GeminiLiveStoragePaths.screenshotsDirectory
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = ScreenshotFilename.formatter.string(from: .now)
        var saved: [String] = []
        var index = 0

        for raw in blocks {
            guard let block = raw as? [String: Any] else { continue }
            guard (block["type"] as? String) == "image" else { continue }
            guard let base64 = block["data"] as? String, !base64.isEmpty else { continue }
            guard let data = Data(base64Encoded: base64) else { continue }

            let mime = block["mimeType"] as? String ?? "image/jpeg"
            let ext = mime.lowercased().contains("png") ? "png" : "jpg"
            let displayName = (block["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let baseName = displayName.flatMap { (($0 as NSString).deletingPathExtension as String).isEmpty ? nil : ($0 as NSString).deletingPathExtension as String } ?? "tab"
            let cleanedBase = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
            let suffix = blocks.count > 1 ? "-\(index)" : ""
            let filename = "\(timestamp)-\(action)-\(cleanedBase)\(suffix).\(ext)"
            let url = directory.appendingPathComponent(filename)

            do {
                try data.write(to: url, options: .atomic)
                saved.append(url.path)
                index += 1
            } catch {
                NotchLog.app.error("Failed to save screenshot to \(url.path): \(error.localizedDescription)")
            }
        }

        return saved
    }

    /// Build a short text content block listing where each screenshot was saved, so
    /// the model and the user can see the on-disk location alongside the image.
    private static func makeSavedScreenshotNote(_ paths: [String]) -> [String: Any]? {
        guard !paths.isEmpty else { return nil }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let pretty = paths.map { path -> String in
            path.hasPrefix(homePath) ? "~" + path.dropFirst(homePath.count) : path
        }
        let body: String
        if pretty.count == 1 {
            body = "Screenshot saved: \(pretty[0])"
        } else {
            body = "Screenshots saved:\n- " + pretty.joined(separator: "\n- ")
        }
        return ["type": "text", "text": body]
    }

    // MARK: - WebSocket

    private static let webSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    private func webSocketAcceptKey(for key: String) -> String {
        let input = Data((key + Self.webSocketGUID).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        input.withUnsafeBytes { pointer in
            _ = CC_SHA1(pointer.baseAddress, CC_LONG(input.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }

    private func handleWebSocketUpgrade(request: String, connection: NWConnection) {
        guard let keyLine = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("sec-websocket-key:") }) else {
            sendPlainTextResponse(status: "400 Bad Request", body: "Missing Sec-WebSocket-Key.", to: connection)
            return
        }

        let key = keyLine.split(separator: ":", maxSplits: 1).dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let accept = webSocketAcceptKey(for: key)
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "",
            "",
        ].joined(separator: "\r\n")

        commandQueue.sync {
            wsConnection?.cancel()
            wsConnection = connection
            wsConnected = true
        }

        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                NotchLog.app.error("Browser bridge WebSocket handshake failed: \(error.localizedDescription)")
                self?.clearWebSocket(connection)
                connection.cancel()
                return
            }
            NotchLog.app.info("Browser bridge WebSocket connected")
            // Push current focus state immediately so extension doesn't need to poll.
            let snap = self?.stateQueue.sync { self?.snapshot ?? FocusBridgeSnapshot() } ?? FocusBridgeSnapshot()
            self?.broadcastFocusState(snapshot: snap)
            self?.receiveWebSocketFrame(on: connection)
        })
    }

    private func clearWebSocket(_ connection: NWConnection) {
        commandQueue.sync {
            if wsConnection === connection {
                wsConnection = nil
                wsConnected = false
                wsParser = BrowserBridgeFrameParser()
            }
        }
    }

    private func receiveWebSocketFrame(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            // Process any data first (even if there's also an error or isComplete).
            if let data, !data.isEmpty {
                NotchLog.app.info("WS received \(data.count) bytes")
                self.commandQueue.sync { self.wsParser.receiveBuffer.append(data) }
                self.drainWebSocketBuffer(connection: connection)
            }

            // Check if the connection was cleared (e.g. by a close frame in drainWebSocketBuffer).
            let stillConnected = self.commandQueue.sync { self.wsConnection === connection }
            guard stillConnected else { return }

            if let error {
                NotchLog.app.error("Browser bridge WebSocket receive failed: \(error.localizedDescription)")
                self.clearWebSocket(connection)
                connection.cancel()
                return
            }
            if isComplete {
                self.clearWebSocket(connection)
                return
            }
            self.receiveWebSocketFrame(on: connection)
        }
    }

    /// Drain all complete messages from the parser buffer and handle each one.
    private func drainWebSocketBuffer(connection: NWConnection) {
        // Collect drained messages outside the sync block so we can call
        // sendWebSocketFrame (which itself sends on the connection) without
        // holding commandQueue.
        let messages: [DrainedMessage] = commandQueue.sync { wsParser.drainMessages() }

        for message in messages {
            switch message {
            case .text(let payload):
                processCompleteMessage(payload: payload)

            case .ping(let pingData):
                // Echo back as pong (opcode 0x0A).
                sendWebSocketFrame(opcode: 0x0A, payload: pingData, to: connection)

            case .close:
                clearWebSocket(connection)
                connection.cancel()
                return
            }
        }
    }

    private func processCompleteMessage(payload: Data) {
        // Fast-path: check the type field before full decode.
        // bridge-keepalive is a no-op; just keeps the connection alive.
        if let rawObj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let type = rawObj["type"] as? String {
            if type == "bridge-keepalive" { return }
            // Only browser-command-result is expected from the extension.
            guard type == "browser-command-result" else {
                NotchLog.app.info("Browser bridge: ignoring unexpected message type '\(type)'")
                return
            }
        }

        guard let result = try? JSONDecoder().decode(BrowserCommandResult.self, from: payload) else {
            NotchLog.app.info("Browser bridge: failed to decode complete message (\(payload.count) bytes)")
            return
        }

        commandQueue.sync {
            commandResults[result.id] = result
            commandWaiters.removeValue(forKey: result.id)?.resume(returning: result)
        }
    }

    private func sendWebSocketFrame(opcode: UInt8, payload: Data, to connection: NWConnection) {
        var frame = Data()
        frame.append(0x80 | opcode)
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            frame.append(126)
            frame.append(UInt8(payload.count >> 8))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error {
                NotchLog.app.error("Browser bridge WebSocket send failed: \(error.localizedDescription)")
            }
        })
    }

    private static let bridgeVersion = 2
}

private enum ScreenshotFilename {
    /// File-name-safe timestamp like "2026-05-09_013700".
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}
