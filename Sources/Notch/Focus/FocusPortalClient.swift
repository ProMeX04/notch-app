import Foundation

struct FocusCloudSyncRequest: Encodable {
    let schemaVersion: Int
    let entries: [FocusDailySyncEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

struct FocusCloudMeResponse: Decodable { let user: FocusCloudUser }
struct FocusCloudProfileResponse: Decodable { let user: FocusCloudUser }

struct FocusCloudUser: Decodable {
    let displayName: String?
    let leaderboardOptIn: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case leaderboardOptIn = "leaderboard_opt_in"
    }
}

struct FocusCloudProfileUpdateRequest: Encodable {
    let leaderboardOptIn: Bool
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case leaderboardOptIn = "leaderboard_opt_in"
        case displayName = "display_name"
    }
}

protocol FocusPortalSyncClient: AnyObject, Sendable {
    func focusSync(configuration: PortalBackendConfiguration, request body: FocusCloudSyncRequest) async throws
    func focusMe(configuration: PortalBackendConfiguration) async throws -> FocusCloudMeResponse
    func updateFocusProfile(configuration: PortalBackendConfiguration, request body: FocusCloudProfileUpdateRequest) async throws -> FocusCloudProfileResponse
}

final class URLSessionFocusPortalClient: FocusPortalSyncClient, @unchecked Sendable {
    private let urlSession: URLSession
    private let jsonDecoder = JSONDecoder()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func focusSync(configuration: PortalBackendConfiguration, request body: FocusCloudSyncRequest) async throws {
        let request = try makeJSONRequest(configuration: configuration, path: "focus/sync", body: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PortalAPIError.invalidResponse
        }
        try validateHTTPStatus(data: data, response: httpResponse)
    }

    func focusMe(configuration: PortalBackendConfiguration) async throws -> FocusCloudMeResponse {
        let request = try makeRequest(configuration: configuration, path: "focus/me", method: "GET")
        return try await decodedResponse(request: request, as: FocusCloudMeResponse.self)
    }

    func updateFocusProfile(configuration: PortalBackendConfiguration, request body: FocusCloudProfileUpdateRequest) async throws -> FocusCloudProfileResponse {
        let request = try makeJSONRequest(configuration: configuration, path: "focus/profile", method: "PATCH", body: body)
        return try await decodedResponse(request: request, as: FocusCloudProfileResponse.self)
    }

    private func decodedResponse<Response: Decodable>(request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PortalAPIError.invalidResponse
        }
        try validateHTTPStatus(data: data, response: httpResponse)
        guard let payload = try? jsonDecoder.decode(type, from: data) else {
            throw PortalAPIError.invalidResponse
        }
        return payload
    }

    private func makeJSONRequest<Body: Encodable>(
        configuration: PortalBackendConfiguration,
        path: String,
        method: String = "POST",
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(configuration: configuration, path: path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func makeRequest(
        configuration: PortalBackendConfiguration,
        path: String,
        method: String
    ) throws -> URLRequest {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = configuration.baseURL.appendingPathComponent(trimmedPath)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue(
            PortalDeviceContext.currentMac(trustDevice: false).deviceID,
            forHTTPHeaderField: "X-Notch-Device-Id"
        )

        if let token = configuration.authorizationToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func validateHTTPStatus(data: Data, response: HTTPURLResponse) throws {
        guard (200 ... 299).contains(response.statusCode) else {
            if let serverMessage = parsedServerErrorMessage(from: data) {
                throw PortalAPIError.server(serverMessage)
            }

            if response.statusCode == 401 || response.statusCode == 403 {
                throw PortalAPIError.unauthorized
            }

            throw PortalAPIError.server("Portal server returned HTTP \(response.statusCode).")
        }
    }

    private func parsedServerErrorMessage(from data: Data) -> String? {
        if let envelope = try? jsonDecoder.decode(ServerErrorEnvelope.self, from: data),
           !envelope.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envelope.error
        }

        if let envelope = try? jsonDecoder.decode(FastAPIErrorEnvelope.self, from: data),
           !envelope.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envelope.detail
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] {
            if let detail = detail as? String,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return detail
            }

            if let detailItems = detail as? [[String: Any]] {
                let messages = detailItems.compactMap { item -> String? in
                    guard let message = item["msg"] as? String else { return nil }
                    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                if !messages.isEmpty {
                    return messages.joined(separator: "\n")
                }
            }
        }

        return nil
    }

    private struct ServerErrorEnvelope: Decodable {
        let error: String
    }

    private struct FastAPIErrorEnvelope: Decodable {
        let detail: String
    }
}
