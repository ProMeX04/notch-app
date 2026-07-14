import Darwin
import Foundation

/// Bridges Notch leisure minutes → Block Shorts & Reels extension.
///
/// Chrome cannot read arbitrary disk paths, so the bridge uses:
/// 1. **Outbox file** under `~/Documents/NotchTOEIC/` (+ Downloads mirror)
/// 2. **Localhost HTTP** `127.0.0.1:20129` for the extension to poll & claim grants
@MainActor
final class TOEICBlockShortsBridge {
    static let shared = TOEICBlockShortsBridge()

    nonisolated static let httpPort: UInt16 = 20129
    nonisolated static let folderName = "NotchTOEIC"
    nonisolated static let outboxFileName = "notch_leisure_outbox.json"
    nonisolated static let ackFileName = "notch_leisure_ack.json"

    private struct Outbox: Codable {
        var schemaVersion: Int
        var updatedAt: String
        var source: String
        var grants: [Grant]
    }

    struct Grant: Codable, Identifiable, Equatable {
        let id: String
        let minutes: Int
        let createdAt: String
        let reason: String
    }

    private struct AckFile: Codable {
        var ackedGrantIds: [String]
        var updatedAt: String?
    }

    private var grants: [Grant] = []
    private var serverRunning = false
    private let iso = ISO8601DateFormatter()
    private let serverQueue = DispatchQueue(label: "dev.notch.toeic.blockshorts-http")

    private init() {
        loadOutboxFromDisk()
        startServerIfNeeded()
    }

    // MARK: - Public

    /// Queue leisure minutes for Block Shorts unlock (`gemini_pending_minutes`).
    func enqueueLeisureMinutes(_ minutes: Int, reason: String) {
        let m = max(0, minutes)
        guard m > 0 else { return }
        let grant = Grant(
            id: UUID().uuidString,
            minutes: m,
            createdAt: iso.string(from: Date()),
            reason: reason
        )
        grants.append(grant)
        persistOutbox()
        startServerIfNeeded()
    }

    func pendingGrants() -> [Grant] {
        applyAcksFromDisk()
        return grants
    }

    func pendingMinutesTotal() -> Int {
        pendingGrants().reduce(0) { $0 + $1.minutes }
    }

    @discardableResult
    func acknowledge(grantIds: [String]) -> Int {
        guard !grantIds.isEmpty else { return 0 }
        let idSet = Set(grantIds)
        let claimed = grants.filter { idSet.contains($0.id) }
        let minutes = claimed.reduce(0) { $0 + $1.minutes }
        grants.removeAll { idSet.contains($0.id) }
        persistOutbox()
        appendAckFile(ids: Array(idSet))
        return minutes
    }

    // MARK: - Paths

    private var documentsOutboxURL: URL {
        folderURL(in: .documentDirectory).appendingPathComponent(Self.outboxFileName)
    }

    private var downloadsOutboxURL: URL {
        folderURL(in: .downloadsDirectory).appendingPathComponent(Self.outboxFileName)
    }

    private var documentsAckURL: URL {
        folderURL(in: .documentDirectory).appendingPathComponent(Self.ackFileName)
    }

    private func folderURL(in directory: FileManager.SearchPathDirectory) -> URL {
        let base = FileManager.default.urls(for: directory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(Self.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Disk

    private func loadOutboxFromDisk() {
        let urls = [documentsOutboxURL, downloadsOutboxURL]
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let box = try? JSONDecoder().decode(Outbox.self, from: data) else { continue }
            grants = box.grants
            applyAcksFromDisk()
            return
        }
    }

    private func persistOutbox() {
        let box = Outbox(
            schemaVersion: 1,
            updatedAt: iso.string(from: Date()),
            source: "notch-macos",
            grants: grants
        )
        guard let data = try? JSONEncoder().encode(box) else { return }
        try? data.write(to: documentsOutboxURL, options: .atomic)
        try? data.write(to: downloadsOutboxURL, options: .atomic)
    }

    private func applyAcksFromDisk() {
        guard let data = try? Data(contentsOf: documentsAckURL),
              let ack = try? JSONDecoder().decode(AckFile.self, from: data) else { return }
        let ids = Set(ack.ackedGrantIds)
        guard !ids.isEmpty else { return }
        grants.removeAll { ids.contains($0.id) }
        persistOutbox()
    }

    private func appendAckFile(ids: [String]) {
        var existing: [String] = []
        if let data = try? Data(contentsOf: documentsAckURL),
           let ack = try? JSONDecoder().decode(AckFile.self, from: data) {
            existing = ack.ackedGrantIds
        }
        let merged = Array(Set(existing + ids))
        let ack = AckFile(ackedGrantIds: merged, updatedAt: iso.string(from: Date()))
        if let data = try? JSONEncoder().encode(ack) {
            try? data.write(to: documentsAckURL, options: .atomic)
            try? data.write(
                to: folderURL(in: .downloadsDirectory).appendingPathComponent(Self.ackFileName),
                options: .atomic
            )
        }
    }

    // MARK: - Localhost HTTP (POSIX loopback — reliable for extension poll)

    func startServerIfNeeded() {
        // Stamp so we can verify bootstrap reached the bridge.
        let stamp = FileManager.default.temporaryDirectory.appendingPathComponent("notch-leisure-bridge-start.txt")
        try? "start \(Date()) serverRunning=\(serverRunning)\n".write(to: stamp, atomically: true, encoding: .utf8)

        guard !serverRunning else { return }
        serverRunning = true
        // Strong capture — accept loop is long-lived for app lifetime.
        serverQueue.async {
            TOEICBlockShortsBridge.shared.runAcceptLoop()
        }
    }

    nonisolated private func runAcceptLoop() {
        func log(_ msg: String) {
            let line = "\(Date()): \(msg)\n"
            if let data = line.data(using: .utf8) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-leisure-bridge.log")
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: url)
                }
            }
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log("socket() failed errno=\(errno)")
            Task { @MainActor in self.serverRunning = false }
            return
        }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(Self.httpPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            log("bind() failed errno=\(errno)")
            close(fd)
            Task { @MainActor in self.serverRunning = false }
            return
        }
        if Darwin.listen(fd, 16) != 0 {
            log("listen() failed errno=\(errno)")
            close(fd)
            Task { @MainActor in self.serverRunning = false }
            return
        }
        log("listening on 127.0.0.1:\(Self.httpPort)")

        while true {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(fd, sockPtr, &len)
                }
            }
            if client < 0 {
                continue
            }
            DispatchQueue.global(qos: .utility).async {
                Self.handleClient(fd: client)
            }
        }
    }

    nonisolated private static func handleClient(fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { return }
        let request = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""

        final class Box: @unchecked Sendable {
            var data = Data()
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            box.data = TOEICBlockShortsBridge.shared.httpResponse(for: request)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
        if !box.data.isEmpty {
            _ = box.data.withUnsafeBytes { raw in
                write(fd, raw.baseAddress, box.data.count)
            }
        }
    }

    private func httpResponse(for request: String) -> Data {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if method == "OPTIONS" {
            return corsPreflight()
        }

        if method == "GET", path.hasPrefix("/v1/leisure/pending") || path.hasPrefix("/v1/block-shorts/leisure/pending") {
            applyAcksFromDisk()
            let body: [String: Any] = [
                "ok": true,
                "pendingMinutes": pendingMinutesTotal(),
                "grants": grants.map { g -> [String: Any] in
                    [
                        "id": g.id,
                        "minutes": g.minutes,
                        "createdAt": g.createdAt,
                        "reason": g.reason,
                    ]
                },
            ]
            return jsonHTTP(status: 200, body: body)
        }

        if method == "POST", path.hasPrefix("/v1/leisure/ack") || path.hasPrefix("/v1/block-shorts/leisure/ack") {
            let bodyData = extractHTTPBody(request)
            var ids: [String] = []
            if let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                if let arr = obj["grantIds"] as? [String] {
                    ids = arr
                } else if let arr = obj["grantIds"] as? [Any] {
                    ids = arr.compactMap { $0 as? String }
                }
            }
            let minutes = acknowledge(grantIds: ids)
            return jsonHTTP(status: 200, body: ["ok": true, "ackedMinutes": minutes, "grantIds": ids])
        }

        if method == "GET", path == "/health" || path == "/v1/health" {
            return jsonHTTP(status: 200, body: [
                "ok": true,
                "service": "notch-block-shorts-bridge",
                "pendingMinutes": pendingMinutesTotal(),
            ])
        }

        return jsonHTTP(status: 404, body: ["ok": false, "error": "not_found"])
    }

    private func extractHTTPBody(_ request: String) -> Data {
        if let range = request.range(of: "\r\n\r\n") {
            return Data(request[range.upperBound...].utf8)
        }
        if let range = request.range(of: "\n\n") {
            return Data(request[range.upperBound...].utf8)
        }
        return Data()
    }

    private func corsPreflight() -> Data {
        let header = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r

        """
        return Data(header.utf8)
    }

    private func jsonHTTP(status: Int, body: [String: Any]) -> Data {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Error"
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(payload.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        var data = Data(header.utf8)
        data.append(payload)
        return data
    }
}
