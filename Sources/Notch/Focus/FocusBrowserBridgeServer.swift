import Combine
import Foundation
import Network
import NotchFocusCore

final class FocusBrowserBridgeServer: @unchecked Sendable {
    private struct FocusBridgeSnapshot {
        var isRunning = false
        var hasActiveSession = false
        var phase = PomodoroPhase.focus.rawValue
        var remainingSeconds = 0
        var blockedHosts: [String] = []

        var focusActive: Bool {
            isRunning && phase == PomodoroPhase.focus.rawValue
        }
    }

    private struct FocusBridgePayload: Codable {
        let app: String
        let bridgeVersion: Int
        let focusActive: Bool
        let isRunning: Bool
        let hasActiveSession: Bool
        let phase: String
        let remainingSeconds: Int
        let blockedHosts: [String]
        let updatedAt: String
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

    @MainActor
    init(pomodoroViewModel: PomodoroViewModel, blocklistStore: FocusWebsiteBlocklistStore) {
        snapshot.isRunning = pomodoroViewModel.isRunning
        snapshot.hasActiveSession = pomodoroViewModel.hasActiveSession
        snapshot.phase = pomodoroViewModel.phase.rawValue
        snapshot.remainingSeconds = pomodoroViewModel.remainingSeconds
        snapshot.blockedHosts = blocklistStore.blockedHosts

        encoder.outputFormatting = [.sortedKeys]

        Publishers.CombineLatest4(
            pomodoroViewModel.$isRunning,
            pomodoroViewModel.$hasActiveSession,
            pomodoroViewModel.$phase,
            pomodoroViewModel.$remainingSeconds
        )
        .sink { [weak self] isRunning, hasActiveSession, phase, remainingSeconds in
            self?.stateQueue.async {
                self?.snapshot.isRunning = isRunning
                self?.snapshot.hasActiveSession = hasActiveSession
                self?.snapshot.phase = phase.rawValue
                self?.snapshot.remainingSeconds = remainingSeconds
            }
        }
        .store(in: &cancellables)

        blocklistStore.$blockedHosts
            .sink { [weak self] blockedHosts in
                self?.stateQueue.async {
                    self?.snapshot.blockedHosts = blockedHosts
                }
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
        case ("GET", "/v1/focus-state"):
            let payload = currentPayload()
            sendJSONResponse(payload, to: connection)
        default:
            sendPlainTextResponse(status: "404 Not Found", body: "Not found.", to: connection)
        }
    }

    private func currentPayload() -> FocusBridgePayload {
        let snapshot = stateQueue.sync { self.snapshot }
        return FocusBridgePayload(
            app: "Notch",
            bridgeVersion: Self.bridgeVersion,
            focusActive: snapshot.focusActive,
            isRunning: snapshot.isRunning,
            hasActiveSession: snapshot.hasActiveSession,
            phase: snapshot.phase,
            remainingSeconds: snapshot.remainingSeconds,
            blockedHosts: snapshot.blockedHosts,
            updatedAt: iso8601Formatter.string(from: .now)
        )
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

    private static let bridgeVersion = 1
}
