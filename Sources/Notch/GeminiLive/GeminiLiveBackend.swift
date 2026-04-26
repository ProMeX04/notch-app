import Foundation

struct GeminiLiveBackendConfiguration: Equatable, Sendable {
    let baseURL: URL
    let clientToken: String?
    let userAccessToken: String?

    var displayURL: String {
        baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var authorizationToken: String? {
        let userToken = normalizedValue(userAccessToken)
        if let userToken {
            return userToken
        }
        return normalizedValue(clientToken)
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

struct GeminiLiveBackendHealthResponse: Decodable {
    let ok: Bool
    let apiVersion: String?
    let mode: String?
    let auth: String?
}

struct GeminiLiveEphemeralTokenResponse: Decodable, Sendable {
    let name: String
    let expireTime: String?
    let newSessionExpireTime: String?
    let uses: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case expireTime = "expire_time"
        case newSessionExpireTime = "new_session_expire_time"
        case uses
    }
}

struct GeminiLiveSessionTokenRequest: Encodable, Sendable {
    let model: String
    let systemInstruction: String?
    let voiceName: String?
    let thinkingBudget: Int?
    let responseModalities: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case systemInstruction = "system_instruction"
        case voiceName = "voice_name"
        case thinkingBudget = "thinking_budget"
        case responseModalities = "response_modalities"
    }
}

struct GeminiLiveBackendAuthUser: Decodable, Equatable, Sendable {
    let id: String
    let email: String
    let name: String?
    let createdAt: String
    /// Present when the API returns `is_pro` (web subscription / server-side Pro).
    let isPro: Bool?
    /// Optional remote feature policy returned by `GET /auth/me`.
    let permissionPolicy: NotchRemotePermissionPolicy?

    init(
        id: String,
        email: String,
        name: String?,
        createdAt: String,
        isPro: Bool?,
        permissionPolicy: NotchRemotePermissionPolicy? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
        self.isPro = isPro
        self.permissionPolicy = permissionPolicy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case createdAt = "created_at"
        case isPro = "is_pro"
        case permissionPolicy = "permission_policy"
    }
}

struct GeminiLiveBackendAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresAt: String
    let refreshToken: String
    let refreshExpiresAt: String
    let user: GeminiLiveBackendAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case refreshToken = "refresh_token"
        case refreshExpiresAt = "refresh_expires_at"
        case user
    }
}

struct GeminiLiveBackendAuthSession: Equatable, Sendable {
    let accessToken: String
    let expiresAt: String
    let refreshToken: String?
    let refreshExpiresAt: String?
    let user: GeminiLiveBackendAuthUser
}

struct GeminiLiveBackendOAuthAuthorizationRequest: Equatable, Sendable {
    static let nativeClientID = "notch-desktop"
    static let redirectURI = "notch://oauth/callback"

    let clientID: String
    let redirectURI: String
    let state: String
    let codeChallenge: String
    let codeChallengeMethod: String

    init(
        clientID: String = Self.nativeClientID,
        redirectURI: String = Self.redirectURI,
        state: String,
        codeChallenge: String,
        codeChallengeMethod: String = "S256"
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.state = state
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }
}

struct GeminiLiveBackendDeviceContext: Encodable, Equatable, Sendable {
    let deviceID: String
    let deviceName: String
    let platform: String
    let trustDevice: Bool

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case trustDevice = "trust_device"
    }

    static func currentMac(trustDevice: Bool = true) -> GeminiLiveBackendDeviceContext {
        let defaults = UserDefaults.standard
        let storageKey = "dev.notch.gemini-live.device-id"
        let existing = defaults.string(forKey: storageKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceID = (existing?.isEmpty == false ? existing : nil) ?? UUID().uuidString
        defaults.set(deviceID, forKey: storageKey)

        let localizedName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostName = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (localizedName?.isEmpty == false ? localizedName : nil)
            ?? (hostName.isEmpty ? nil : hostName)
            ?? "This Mac"

        return GeminiLiveBackendDeviceContext(
            deviceID: deviceID,
            deviceName: resolvedName,
            platform: "macOS",
            trustDevice: trustDevice
        )
    }
}

private struct GeminiLiveBackendAuthRequest: Encodable, Sendable {
    let email: String
    let password: String
    let deviceID: String
    let deviceName: String
    let platform: String
    let trustDevice: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case trustDevice = "trust_device"
    }
}

private struct GeminiLiveBackendSignupRequest: Encodable, Sendable {
    let email: String
    let password: String
    let name: String?
    let deviceID: String
    let deviceName: String
    let platform: String
    let trustDevice: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case name
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case trustDevice = "trust_device"
    }
}

private struct GeminiLiveBackendRefreshRequest: Encodable, Sendable {
    let refreshToken: String
    let deviceID: String
    let deviceName: String
    let platform: String
    let trustDevice: Bool

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case trustDevice = "trust_device"
    }
}

private struct GeminiLiveBackendOAuthCodeExchangeRequest: Encodable, Sendable {
    let grantType: String
    let clientID: String
    let redirectURI: String
    let code: String
    let codeVerifier: String
    let deviceID: String
    let deviceName: String
    let platform: String
    let trustDevice: Bool

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
        case code
        case codeVerifier = "code_verifier"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case trustDevice = "trust_device"
    }
}

private struct GeminiLiveBackendLogoutRequest: Encodable, Sendable {
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

enum GeminiLiveBackendError: LocalizedError {
    case missingBaseURL
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case server(String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "Gemini Live server URL is missing."
        case .invalidBaseURL:
            return "Gemini Live server URL is invalid."
        case .invalidResponse:
            return "Gemini Live server returned an invalid response."
        case .unauthorized:
            return "Gemini Live server rejected the current login or token."
        case let .server(message):
            return message
        case .invalidTokenResponse:
            return "Gemini Live server returned an invalid ephemeral token."
        }
    }
}

final class GeminiLiveBackendConfigStore {
    private let defaults: UserDefaults
    private let urlDefaultsKey = "dev.notch.gemini-live.backend-url"
    private let tokenStore: GeminiLiveSecretStore
    private let processInfo: ProcessInfo

    init(processInfo: ProcessInfo, defaults: UserDefaults = .standard) {
        self.processInfo = processInfo
        self.defaults = defaults
        tokenStore = GeminiLiveSecretStore(
            processInfo: processInfo,
            developmentFileURL: GeminiLiveStoragePaths.developmentGeminiLiveClientTokenFile,
            keychainAccount: "GeminiLiveBackendClientToken"
        )
    }

    func read() -> GeminiLiveBackendConfiguration? {
        let env = processInfo.environment
        let rawURL = normalizedValue(
            env["NOTCH_GEMINI_LIVE_BACKEND_URL"]
                ?? defaults.string(forKey: urlDefaultsKey)
        )
        guard let rawURL else { return nil }
        guard let url = normalizedURL(from: rawURL) else { return nil }

        let token = normalizedValue(env["NOTCH_GEMINI_LIVE_CLIENT_TOKEN"] ?? tokenStore.read())
        return GeminiLiveBackendConfiguration(baseURL: url, clientToken: token, userAccessToken: nil)
    }

    @discardableResult
    func save(baseURLString: String, clientToken: String?) -> Bool {
        guard let url = normalizedURL(from: baseURLString) else { return false }

        defaults.set(url.absoluteString, forKey: urlDefaultsKey)

        if let token = normalizedValue(clientToken) {
            return tokenStore.save(token)
        }

        tokenStore.delete()
        return true
    }

    func delete() {
        defaults.removeObject(forKey: urlDefaultsKey)
        tokenStore.delete()
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty, url.host != nil else {
            return nil
        }

        if url.path.isEmpty {
            return url.appendingPathComponent("")
        }
        return url
    }
}

final class GeminiLiveBackendAuthStore {
    private let defaults: UserDefaults
    private let accessTokenStore: GeminiLiveSecretStore
    private let refreshTokenStore: GeminiLiveSecretStore
    private let lastEmailDefaultsKey = "dev.notch.gemini-live.backend-auth.last-email"
    private let lastNameDefaultsKey = "dev.notch.gemini-live.backend-auth.last-name"
    private let lastUserIDDefaultsKey = "dev.notch.gemini-live.backend-auth.last-user-id"
    private let lastIsProDefaultsKey = "dev.notch.gemini-live.backend-auth.last-is-pro"
    private let expiresAtDefaultsKey = "dev.notch.gemini-live.backend-auth.expires-at"
    private let refreshExpiresAtDefaultsKey = "dev.notch.gemini-live.backend-auth.refresh-expires-at"
    private let permissionPolicyDefaultsKey = "dev.notch.gemini-live.backend-auth.permission-policy"
    private let processInfo: ProcessInfo

    init(processInfo: ProcessInfo, defaults: UserDefaults = .standard) {
        self.processInfo = processInfo
        self.defaults = defaults
        accessTokenStore = GeminiLiveSecretStore(
            processInfo: processInfo,
            developmentFileURL: GeminiLiveStoragePaths.developmentGeminiLiveAuthTokenFile,
            keychainAccount: "GeminiLiveBackendAccessToken"
        )
        refreshTokenStore = GeminiLiveSecretStore(
            processInfo: processInfo,
            developmentFileURL: GeminiLiveStoragePaths.developmentGeminiLiveRefreshTokenFile,
            keychainAccount: "GeminiLiveBackendRefreshToken"
        )
    }

    func read() -> GeminiLiveBackendAuthSession? {
        let env = processInfo.environment
        let accessToken = normalizedValue(env["NOTCH_GEMINI_LIVE_ACCESS_TOKEN"] ?? accessTokenStore.read())
        guard let accessToken else { return nil }

        let email = normalizedValue(env["NOTCH_GEMINI_LIVE_AUTH_EMAIL"] ?? defaults.string(forKey: lastEmailDefaultsKey)) ?? ""
        guard !email.isEmpty else { return nil }

        let name = normalizedValue(env["NOTCH_GEMINI_LIVE_AUTH_NAME"] ?? defaults.string(forKey: lastNameDefaultsKey))
        let expiresAt = normalizedValue(env["NOTCH_GEMINI_LIVE_AUTH_EXPIRES_AT"] ?? defaults.string(forKey: expiresAtDefaultsKey)) ?? ""
        let refreshToken = normalizedValue(env["NOTCH_GEMINI_LIVE_REFRESH_TOKEN"] ?? refreshTokenStore.read())
        let refreshExpiresAt = normalizedValue(
            env["NOTCH_GEMINI_LIVE_REFRESH_EXPIRES_AT"] ?? defaults.string(forKey: refreshExpiresAtDefaultsKey)
        )
        let userID = normalizedValue(env["NOTCH_GEMINI_LIVE_AUTH_USER_ID"] ?? defaults.string(forKey: lastUserIDDefaultsKey)) ?? ""
        let isPro = env["NOTCH_GEMINI_LIVE_AUTH_IS_PRO"].flatMap { value -> Bool? in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes"].contains(normalized) { return true }
            if ["0", "false", "no"].contains(normalized) { return false }
            return nil
        } ?? (defaults.object(forKey: lastIsProDefaultsKey) as? Bool)

        if let refreshExpiresAt,
           let refreshExpiresDate = Self.parseISO8601(refreshExpiresAt),
           refreshExpiresDate <= Date() {
            delete()
            return nil
        }

        if refreshToken == nil,
           let expiresDate = Self.parseISO8601(expiresAt),
           expiresDate <= Date() {
            delete()
            return nil
        }

        // Restore the persisted permission policy so the app uses the correct
        // feature flags (e.g. talk_connection = free) immediately on launch,
        // before the async /auth/me refresh has a chance to run.
        let permissionPolicy: NotchRemotePermissionPolicy?
        if let policyData = defaults.data(forKey: permissionPolicyDefaultsKey),
           let decoded = try? JSONDecoder().decode(NotchRemotePermissionPolicy.self, from: policyData) {
            permissionPolicy = decoded
        } else {
            permissionPolicy = nil
        }

        return GeminiLiveBackendAuthSession(
            accessToken: accessToken,
            expiresAt: expiresAt,
            refreshToken: refreshToken,
            refreshExpiresAt: refreshExpiresAt,
            user: GeminiLiveBackendAuthUser(id: userID, email: email, name: name, createdAt: "", isPro: isPro, permissionPolicy: permissionPolicy)
        )
    }

    @discardableResult
    func save(_ session: GeminiLiveBackendAuthSession) -> Bool {
        defaults.set(session.user.email, forKey: lastEmailDefaultsKey)
        defaults.set(session.user.name, forKey: lastNameDefaultsKey)
        defaults.set(session.user.id, forKey: lastUserIDDefaultsKey)
        defaults.set(session.user.isPro ?? false, forKey: lastIsProDefaultsKey)
        defaults.set(session.expiresAt, forKey: expiresAtDefaultsKey)
        if let refreshExpiresAt = session.refreshExpiresAt {
            defaults.set(refreshExpiresAt, forKey: refreshExpiresAtDefaultsKey)
        } else {
            defaults.removeObject(forKey: refreshExpiresAtDefaultsKey)
        }

        // Persist the remote permission policy so it survives across app launches.
        if let policy = session.user.permissionPolicy,
           let policyData = try? JSONEncoder().encode(policy) {
            defaults.set(policyData, forKey: permissionPolicyDefaultsKey)
        } else {
            defaults.removeObject(forKey: permissionPolicyDefaultsKey)
        }

        let didSaveAccess = accessTokenStore.save(session.accessToken)
        let didSaveRefresh: Bool
        if let refreshToken = session.refreshToken, !refreshToken.isEmpty {
            didSaveRefresh = refreshTokenStore.save(refreshToken)
        } else {
            refreshTokenStore.delete()
            didSaveRefresh = true
        }

        return didSaveAccess && didSaveRefresh
    }

    func saveLastEmail(_ email: String) {
        defaults.set(email, forKey: lastEmailDefaultsKey)
    }

    func readLastEmail() -> String {
        defaults.string(forKey: lastEmailDefaultsKey) ?? ""
    }

    func delete() {
        defaults.removeObject(forKey: lastEmailDefaultsKey)
        defaults.removeObject(forKey: lastNameDefaultsKey)
        defaults.removeObject(forKey: lastUserIDDefaultsKey)
        defaults.removeObject(forKey: lastIsProDefaultsKey)
        defaults.removeObject(forKey: expiresAtDefaultsKey)
        defaults.removeObject(forKey: refreshExpiresAtDefaultsKey)
        defaults.removeObject(forKey: permissionPolicyDefaultsKey)
        accessTokenStore.delete()
        refreshTokenStore.delete()
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

final class GeminiLiveBackendClient: @unchecked Sendable {
    private let urlSession: URLSession
    private let jsonDecoder = JSONDecoder()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func validate(configuration: GeminiLiveBackendConfiguration) async throws {
        let request = try makeRequest(
            configuration: configuration,
            path: "gemini-live/health",
            method: "GET"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiLiveBackendError.invalidResponse
        }

        try validateHTTPStatus(data: data, response: httpResponse)

        if let payload = try? jsonDecoder.decode(GeminiLiveBackendHealthResponse.self, from: data),
           payload.ok {
            return
        }

        throw GeminiLiveBackendError.invalidResponse
    }

    func createSessionToken(
        configuration: GeminiLiveBackendConfiguration,
        requestBody: GeminiLiveSessionTokenRequest
    ) async throws -> GeminiLiveEphemeralTokenResponse {
        let request = try makeJSONRequest(
            configuration: configuration,
            path: "gemini-live/session-token",
            body: requestBody
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiLiveBackendError.invalidResponse
        }

        try validateHTTPStatus(data: data, response: httpResponse)

        guard let token = try? jsonDecoder.decode(GeminiLiveEphemeralTokenResponse.self, from: data),
              token.name.hasPrefix("auth_tokens/") else {
            throw GeminiLiveBackendError.invalidTokenResponse
        }
        return token
    }

    func signup(
        configuration: GeminiLiveBackendConfiguration,
        email: String,
        password: String,
        name: String?,
        device: GeminiLiveBackendDeviceContext = .currentMac()
    ) async throws -> GeminiLiveBackendAuthSession {
        try await authenticate(
            configuration: configuration,
            path: "auth/register",
            body: GeminiLiveBackendSignupRequest(
                email: email,
                password: password,
                name: normalizedValue(name),
                deviceID: device.deviceID,
                deviceName: device.deviceName,
                platform: device.platform,
                trustDevice: device.trustDevice
            )
        )
    }

    func login(
        configuration: GeminiLiveBackendConfiguration,
        email: String,
        password: String,
        device: GeminiLiveBackendDeviceContext = .currentMac()
    ) async throws -> GeminiLiveBackendAuthSession {
        try await authenticate(
            configuration: configuration,
            path: "auth/login",
            body: GeminiLiveBackendAuthRequest(
                email: email,
                password: password,
                deviceID: device.deviceID,
                deviceName: device.deviceName,
                platform: device.platform,
                trustDevice: device.trustDevice
            )
        )
    }

    func refresh(
        configuration: GeminiLiveBackendConfiguration,
        refreshToken: String,
        device: GeminiLiveBackendDeviceContext = .currentMac(trustDevice: false)
    ) async throws -> GeminiLiveBackendAuthSession {
        try await authenticate(
            configuration: configuration,
            path: "auth/refresh",
            body: GeminiLiveBackendRefreshRequest(
                refreshToken: refreshToken,
                deviceID: device.deviceID,
                deviceName: device.deviceName,
                platform: device.platform,
                trustDevice: device.trustDevice
            )
        )
    }

    func exchangeOAuthAuthorizationCode(
        configuration: GeminiLiveBackendConfiguration,
        code: String,
        codeVerifier: String,
        authorizationRequest: GeminiLiveBackendOAuthAuthorizationRequest,
        device: GeminiLiveBackendDeviceContext = .currentMac()
    ) async throws -> GeminiLiveBackendAuthSession {
        try await authenticate(
            configuration: configuration,
            path: "oauth/token",
            body: GeminiLiveBackendOAuthCodeExchangeRequest(
                grantType: "authorization_code",
                clientID: authorizationRequest.clientID,
                redirectURI: authorizationRequest.redirectURI,
                code: code,
                codeVerifier: codeVerifier,
                deviceID: device.deviceID,
                deviceName: device.deviceName,
                platform: device.platform,
                trustDevice: device.trustDevice
            )
        )
    }

    func me(configuration: GeminiLiveBackendConfiguration) async throws -> GeminiLiveBackendAuthUser {
        let request = try makeRequest(
            configuration: configuration,
            path: "auth/me",
            method: "GET"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiLiveBackendError.invalidResponse
        }

        try validateHTTPStatus(data: data, response: httpResponse)

        guard let user = try? jsonDecoder.decode(GeminiLiveBackendAuthUser.self, from: data) else {
            throw GeminiLiveBackendError.invalidResponse
        }
        return user
    }

    func logout(configuration: GeminiLiveBackendConfiguration, refreshToken: String?) async throws {
        let request = try makeJSONRequest(
            configuration: configuration,
            path: "auth/logout",
            body: GeminiLiveBackendLogoutRequest(refreshToken: normalizedValue(refreshToken))
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiLiveBackendError.invalidResponse
        }

        try validateHTTPStatus(data: data, response: httpResponse)
    }

    private func authenticate<Body: Encodable>(
        configuration: GeminiLiveBackendConfiguration,
        path: String,
        body: Body
    ) async throws -> GeminiLiveBackendAuthSession {
        let request = try makeJSONRequest(configuration: configuration, path: path, body: body)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiLiveBackendError.invalidResponse
        }

        try validateHTTPStatus(data: data, response: httpResponse)

        guard let payload = try? jsonDecoder.decode(GeminiLiveBackendAuthTokenResponse.self, from: data) else {
            throw GeminiLiveBackendError.invalidResponse
        }

        return GeminiLiveBackendAuthSession(
            accessToken: payload.accessToken,
            expiresAt: payload.expiresAt,
            refreshToken: payload.refreshToken,
            refreshExpiresAt: payload.refreshExpiresAt,
            user: payload.user
        )
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeJSONRequest<Body: Encodable>(
        configuration: GeminiLiveBackendConfiguration,
        path: String,
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(configuration: configuration, path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func makeRequest(
        configuration: GeminiLiveBackendConfiguration,
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
            GeminiLiveBackendDeviceContext.currentMac(trustDevice: false).deviceID,
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
                throw GeminiLiveBackendError.server(serverMessage)
            }

            if response.statusCode == 401 || response.statusCode == 403 {
                throw GeminiLiveBackendError.unauthorized
            }

            throw GeminiLiveBackendError.server("Gemini Live server returned HTTP \(response.statusCode).")
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
