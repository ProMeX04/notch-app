import Foundation

@MainActor
final class BackendAccountCoordinator: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var signedInSummary: String?
    @Published private(set) var authenticatedEmail: String?
    @Published private(set) var isProFromBackend = false
    @Published private(set) var lastError: String?

    private let client: GeminiLiveBackendClient
    private let configStore: GeminiLiveBackendConfigStore
    private let authStore: GeminiLiveBackendAuthStore
    private var storedAuthSession: GeminiLiveBackendAuthSession?
    private var authRefreshTask: Task<GeminiLiveBackendAuthSession, Error>?
    private var logoutRetryTask: Task<Void, Never>?

    var onAuthChanged: (@MainActor () -> Void)?
    var onProChanged: (@MainActor (Bool) -> Void)?
    var onStatusChange: (@MainActor (String?) -> Void)?
    var onErrorChange: (@MainActor (String?) -> Void)?
    var onSavingStateChange: (@MainActor (Bool) -> Void)?
    var onAuthEmailChange: (@MainActor (String) -> Void)?
    var currentDraftEmailProvider: (@MainActor () -> String?)?
    var ensureConfigurationForAuth: (@MainActor () async -> GeminiLiveBackendConfiguration?)?
    var currentConfigurationProvider: (@MainActor () -> GeminiLiveBackendConfiguration?)?
    var shouldDisconnectManagedSession: (@MainActor () -> Bool)?
    var disconnectManagedSession: (@MainActor () -> Void)?

    init(
        client: GeminiLiveBackendClient,
        configStore: GeminiLiveBackendConfigStore,
        authStore: GeminiLiveBackendAuthStore
    ) {
        self.client = client
        self.configStore = configStore
        self.authStore = authStore
        loadCurrentAuth()
    }

    var currentAccessToken: String? {
        storedAuthSession?.accessToken
    }

    var lastKnownEmail: String {
        authStore.readLastEmail()
    }

    var authorizationToken: String? {
        configuredBackendConfigurationWithAuth?.authorizationToken
    }

    func signup(email: String, password: String, name: String?) async -> Bool {
        guard let configuration = await ensureResolvedConfigurationForAuth() else {
            setLastError("Gemini Live server URL is missing.")
            setStatus("Check the connection and try again.")
            return false
        }
        guard !email.isEmpty else {
            setLastError("Email is missing.")
            setStatus("Enter your email, then try again.")
            return false
        }
        guard !password.isEmpty else {
            setLastError("Password is missing.")
            setStatus("Enter your password, then try again.")
            return false
        }
        guard password.count >= 8 else {
            setLastError("Password must be at least 8 characters.")
            setStatus("Use a longer password, then try again.")
            return false
        }

        setSaving(true)
        setLastError(nil)
        setStatus("Creating your server account...")
        defer { setSaving(false) }
        authStore.saveLastEmail(email)

        do {
            let session = try await client.signup(
                configuration: configuration,
                email: email,
                password: password,
                name: name
            )
            storeBackendAuthSession(session)
            setStatus(nil)
            return true
        } catch {
            setLastError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            setStatus("Couldn't create your server account.")
            return false
        }
    }

    func login(email: String, password: String) async -> Bool {
        guard let configuration = await ensureResolvedConfigurationForAuth() else {
            setLastError("Gemini Live server URL is missing.")
            setStatus("Check the connection and try again.")
            return false
        }
        guard !email.isEmpty else {
            setLastError("Email is missing.")
            setStatus("Enter your email, then try again.")
            return false
        }
        guard !password.isEmpty else {
            setLastError("Password is missing.")
            setStatus("Enter your password, then try again.")
            return false
        }
        guard password.count >= 8 else {
            setLastError("Password must be at least 8 characters.")
            setStatus("Use a longer password, then try again.")
            return false
        }

        setSaving(true)
        setLastError(nil)
        setStatus("Signing in to Gemini Live server...")
        defer { setSaving(false) }
        authStore.saveLastEmail(email)

        do {
            let session = try await client.login(
                configuration: configuration,
                email: email,
                password: password
            )
            storeBackendAuthSession(session)
            setStatus(nil)
            return true
        } catch {
            setLastError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            setStatus("Couldn't sign in to Gemini Live server.")
            return false
        }
    }

    func applyWebSessionToken(_ rawToken: String) async -> Bool {
        let token = Self.normalizedPastedAccessToken(rawToken)
        guard !token.isEmpty else {
            setLastError("Session token is empty.")
            return false
        }
        guard await ensureResolvedConfigurationForAuth() != nil else {
            setLastError("Gemini Live server URL is missing.")
            return false
        }
        guard let configuration = configuredBackendConfiguration else {
            setLastError("Gemini Live server URL is missing.")
            return false
        }

        setSaving(true)
        setLastError(nil)
        defer { setSaving(false) }

        let portableSession = Self.decodedPortableBackendAuthSession(from: token)
        let accessToken = portableSession?.accessToken ?? token
        let withToken = GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: accessToken
        )

        do {
            let user = try await client.me(configuration: withToken)
            let session = GeminiLiveBackendAuthSession(
                accessToken: accessToken,
                expiresAt: portableSession?.expiresAt ?? Self.iso8601ExpiryForPastedSession(),
                refreshToken: portableSession?.refreshToken,
                refreshExpiresAt: portableSession?.refreshExpiresAt,
                user: user
            )
            storeBackendAuthSession(session)
            await refreshSubscriptionStatus()
            return true
        } catch {
            setLastError("Invalid or expired session token.")
            return false
        }
    }

    func logout() async {
        let configuration = configuredBackendUserConfiguration
        let refreshToken = storedAuthSession?.refreshToken
        let shouldDisconnectManagedSession = shouldDisconnectManagedSession?() ?? false

        setSaving(true)
        defer { setSaving(false) }
        setLastError(nil)

        if shouldDisconnectManagedSession {
            disconnectManagedSession?()
        }

        clearBackendAuthSession()
        setStatus(configuredBackendConfiguration == nil ? "Gemini Live server saved. Sign in to continue." : "Signed out from Gemini Live server.")

        guard let configuration else { return }

        logoutRetryTask?.cancel()
        logoutRetryTask = Task.detached(priority: .utility) { [client] in
            let retryDelays: [Duration] = [.zero, .seconds(2), .seconds(5)]

            for delay in retryDelays {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }

                do {
                    try await client.logout(configuration: configuration, refreshToken: refreshToken)
                    return
                } catch {
                    continue
                }
            }
        }
    }

    func refreshSubscriptionStatus() async {
        guard let configuration = await freshConfiguredBackendUserConfiguration() else {
            setProFromBackend(false)
            return
        }

        do {
            let user = try await client.me(configuration: configuration)
            setProFromBackend(user.isPro ?? false)
        } catch {
            if shouldClearBackendAuthSession(for: error) {
                clearBackendAuthSession()
                return
            }
            // Keep previous backend Pro flag if the request fails (offline, etc.).
        }
    }

    func openWebProCheckout() {
        Task {
            guard let configuration = await self.freshConfiguredBackendUserConfiguration() else {
                NotchWebPortal.openInBrowser(NotchWebPortal.proCheckoutURL())
                return
            }

            do {
                let bridge = try await client.createWebBridgeToken(configuration: configuration)
                let url = NotchWebPortal.authBridgeURL(token: bridge.bridgeToken)
                NotchWebPortal.openInBrowser(url)
            } catch {
                await MainActor.run {
                    self.setLastError(error.localizedDescription)
                }
                NotchWebPortal.openInBrowser(NotchWebPortal.proCheckoutURL())
            }
        }
    }

    func reloadCurrentAuth() {
        loadCurrentAuth()
    }

    func freshConfiguredBackendUserConfiguration(forceRefresh: Bool = false) async -> GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration,
              let session = await refreshBackendAuthSessionIfNeeded(forceRefresh: forceRefresh) else {
            return nil
        }

        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: nil,
            userAccessToken: session.accessToken
        )
    }

    func clearBackendAuthSession() {
        let preservedEmail = currentDraftEmailProvider?()
        authRefreshTask?.cancel()
        authRefreshTask = nil
        authStore.delete()
        if let preservedEmail {
            authStore.saveLastEmail(preservedEmail)
        }
        storedAuthSession = nil
        updatePublishedAuthState()
        setProFromBackend(false)
        onAuthChanged?()
    }

    func shouldClearBackendAuthSession(for error: Error) -> Bool {
        if let backendError = error as? GeminiLiveBackendError {
            switch backendError {
            case .unauthorized:
                return true
            case let .server(message):
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized.contains("invalid or expired session token")
                    || normalized.contains("session token")
                    || normalized.contains("unauthorized")
            default:
                return false
            }
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return description.contains("invalid or expired session token")
            || description.contains("unauthorized")
    }

    func shutdown() {
        authRefreshTask?.cancel()
        authRefreshTask = nil
        logoutRetryTask?.cancel()
        logoutRetryTask = nil
    }

    private var configuredBackendConfiguration: GeminiLiveBackendConfiguration? {
        currentConfigurationProvider?() ?? configStore.read()
    }

    private var configuredBackendConfigurationForAuth: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: nil
        )
    }

    private var configuredBackendConfigurationWithAuth: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: storedAuthSession?.accessToken
        )
    }

    private var configuredBackendUserConfiguration: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration,
              let session = storedAuthSession else {
            return nil
        }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: nil,
            userAccessToken: session.accessToken
        )
    }

    private func ensureResolvedConfigurationForAuth() async -> GeminiLiveBackendConfiguration? {
        if let ensureConfigurationForAuth {
            return await ensureConfigurationForAuth()
        }
        return configuredBackendConfigurationForAuth
    }

    private func parsedISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func backendAccessTokenNeedsRefresh(_ session: GeminiLiveBackendAuthSession) -> Bool {
        guard let expiresAt = parsedISO8601Date(session.expiresAt) else { return true }
        return expiresAt <= Date().addingTimeInterval(5 * 60)
    }

    private func backendRefreshTokenExpired(_ session: GeminiLiveBackendAuthSession) -> Bool {
        guard let refreshExpiresAt = session.refreshExpiresAt else { return false }
        guard let expiresAt = parsedISO8601Date(refreshExpiresAt) else { return true }
        return expiresAt <= Date()
    }

    private func loadCurrentAuth() {
        storedAuthSession = authStore.read()
        updatePublishedAuthState()
        setProFromBackend(storedAuthSession?.user.isPro ?? false)
    }

    private func refreshBackendAuthSessionIfNeeded(forceRefresh: Bool = false) async -> GeminiLiveBackendAuthSession? {
        guard let session = storedAuthSession ?? authStore.read() else {
            storedAuthSession = nil
            updatePublishedAuthState()
            return nil
        }

        if storedAuthSession == nil {
            storedAuthSession = session
            updatePublishedAuthState()
        }

        if backendRefreshTokenExpired(session) {
            clearBackendAuthSession()
            return nil
        }

        if !forceRefresh && !backendAccessTokenNeedsRefresh(session) {
            return session
        }

        guard let refreshToken = session.refreshToken,
              !refreshToken.isEmpty,
              let configuration = configuredBackendConfigurationForAuth else {
            if let accessExpiry = parsedISO8601Date(session.expiresAt), accessExpiry > Date(), !forceRefresh {
                return session
            }
            clearBackendAuthSession()
            return nil
        }

        if let authRefreshTask {
            do {
                let refreshedSession = try await authRefreshTask.value
                storeBackendAuthSession(refreshedSession)
                return refreshedSession
            } catch {
                if shouldClearBackendAuthSession(for: error) {
                    clearBackendAuthSession()
                }
                return nil
            }
        }

        let task = Task { [client] in
            try await client.refresh(configuration: configuration, refreshToken: refreshToken)
        }
        authRefreshTask = task
        defer { authRefreshTask = nil }

        do {
            let refreshedSession = try await task.value
            storeBackendAuthSession(refreshedSession)
            return refreshedSession
        } catch {
            if shouldClearBackendAuthSession(for: error) {
                clearBackendAuthSession()
            } else if let accessExpiry = parsedISO8601Date(session.expiresAt), accessExpiry > Date(), !forceRefresh {
                return session
            }
            return nil
        }
    }

    private func storeBackendAuthSession(_ session: GeminiLiveBackendAuthSession) {
        _ = authStore.save(session)
        storedAuthSession = session
        authStore.saveLastEmail(session.user.email)
        onAuthEmailChange?(session.user.email)
        setLastError(nil)
        updatePublishedAuthState()
        setProFromBackend(session.user.isPro ?? false)
        onAuthChanged?()
    }

    private func updatePublishedAuthState() {
        authenticatedEmail = storedAuthSession?.user.email
        signedInSummary = authenticatedEmail
        isAuthenticated = storedAuthSession != nil
    }

    private func setProFromBackend(_ newValue: Bool) {
        let didChange = isProFromBackend != newValue
        isProFromBackend = newValue
        if didChange {
            onProChanged?(newValue)
        }
    }

    private func setStatus(_ message: String?) {
        onStatusChange?(message)
    }

    private func setLastError(_ message: String?) {
        lastError = message
        onErrorChange?(message)
    }

    private func setSaving(_ isSaving: Bool) {
        onSavingStateChange?(isSaving)
    }

    private struct PortableBackendAuthSession: Decodable {
        let accessToken: String
        let expiresAt: String
        let refreshToken: String?
        let refreshExpiresAt: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
            case refreshToken = "refresh_token"
            case refreshExpiresAt = "refresh_expires_at"
        }
    }

    private static func normalizedPastedAccessToken(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let prefix = "Bearer "
        if t.lowercased().hasPrefix(prefix.lowercased()) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2) || (t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private static func decodedPortableBackendAuthSession(from token: String) -> PortableBackendAuthSession? {
        let prefix = "nts_"
        guard token.hasPrefix(prefix) else { return nil }

        let encoded = String(token.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: Self.base64URLToBase64(encoded)) else { return nil }
        return try? JSONDecoder().decode(PortableBackendAuthSession.self, from: data)
    }

    private static func base64URLToBase64(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = replaced.count % 4
        guard remainder != 0 else { return replaced }
        return replaced + String(repeating: "=", count: 4 - remainder)
    }

    private static func iso8601ExpiryForPastedSession() -> String {
        let date = Date().addingTimeInterval(30 * 24 * 3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var s = formatter.string(from: date)
        if s.hasSuffix("+00:00") {
            s = String(s.dropLast(6)) + "Z"
        }
        return s
    }
}
