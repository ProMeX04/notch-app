import CryptoKit
import Foundation

enum BackendAuthResetReason: Equatable {
    case unauthorized
    case invalidSession
    case invalidRefreshToken
    case expiredSession
}

enum BackendAuthFailure: Equatable {
    case unauthorized
    case server(message: String, resetReason: BackendAuthResetReason?)
    case other(message: String)
}

enum BackendAuthPhase: Equatable {
    case signedOut
    case signingIn
    case authenticated(GeminiLiveBackendAuthSession)
    case refreshing(GeminiLiveBackendAuthSession)
    case failed(BackendAuthFailure)
}

@MainActor
final class BackendAccountCoordinator: ObservableObject {
    @Published private(set) var authPhase: BackendAuthPhase = .signedOut
    @Published private(set) var isAuthenticated = false
    @Published private(set) var signedInSummary: String?
    @Published private(set) var authenticatedEmail: String?
    @Published private(set) var isProFromBackend = false
    @Published private(set) var lastError: String?

    private let client: GeminiLiveBackendClient
    private let configStore: GeminiLiveBackendConfigStore
    private let authStore: GeminiLiveBackendAuthStore
    private let entitlementStore: NotchEntitlementStore?
    private var storedAuthSession: GeminiLiveBackendAuthSession?
    private var authRefreshTask: Task<GeminiLiveBackendAuthSession, Error>?
    private var logoutRetryTask: Task<Void, Never>?
    private var pendingOAuthFlow: PendingOAuthFlow?

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
        authStore: GeminiLiveBackendAuthStore,
        entitlementStore: NotchEntitlementStore? = nil
    ) {
        self.client = client
        self.configStore = configStore
        self.authStore = authStore
        self.entitlementStore = entitlementStore
        loadCurrentAuth()
    }

    var currentAccessToken: String? {
        currentAuthSession?.accessToken
    }

    var lastKnownEmail: String {
        authStore.readLastEmail()
    }

    var authorizationToken: String? {
        currentAccessToken
    }

    var shouldShowAuthError: Bool {
        if case .failed = authPhase { return true }
        return false
    }

    var authPhaseDescription: String? {
        switch authPhase {
        case .signedOut, .authenticated, .refreshing:
            return nil
        case .signingIn:
            return "Signing in"
        case let .failed(failure):
            switch failure {
            case .unauthorized:
                return "Unauthorized"
            case let .server(message, _):
                return message
            case let .other(message):
                return message
            }
        }
    }

    var isAuthRefreshInFlight: Bool {
        if case .refreshing = authPhase { return true }
        return false
    }

    var isSigningIn: Bool {
        if case .signingIn = authPhase { return true }
        return false
    }

    var currentAuthFailure: BackendAuthFailure? {
        if case let .failed(failure) = authPhase { return failure }
        return nil
    }

    var currentResetReason: BackendAuthResetReason? {
        if case let .failed(failure) = authPhase {
            switch failure {
            case .unauthorized:
                return .unauthorized
            case let .server(_, resetReason):
                return resetReason
            case .other:
                return nil
            }
        }
        return nil
    }

    private var currentAuthSession: GeminiLiveBackendAuthSession? {
        switch authPhase {
        case let .authenticated(session), let .refreshing(session):
            return session
        default:
            return storedAuthSession
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
                if delay > .zero { try? await Task.sleep(for: delay) }
                do {
                    try await client.logout(configuration: configuration, refreshToken: refreshToken)
                    return
                } catch {
                    continue
                }
            }
        }
    }

    func refreshSubscriptionStatus(forceRefresh: Bool = false) async {
        guard let configuration = await freshConfiguredBackendUserConfiguration(forceRefresh: forceRefresh) else {
            if storedAuthSession == nil {
                setProFromBackend(false)
                entitlementStore?.markSignedOut()
            } else {
                entitlementStore?.markRefreshFailed()
            }
            return
        }

        do {
            let user = try await client.me(configuration: configuration)
            syncAuthenticatedUser(user)
            setLastError(nil)
        } catch {
            if shouldClearBackendAuthSession(for: error) {
                clearBackendAuthSession()
            } else {
                entitlementStore?.markRefreshFailed()
            }
        }
    }

    func openWebAccountLogin() {
        Task {
            guard let configuration = await ensureResolvedConfigurationForAuth() else {
                setLastError("Gemini Live server URL is missing.")
                setStatus("Check the connection and try again.")
                NotchWebPortal.openInBrowser(NotchWebPortal.loginURL(apiBaseURL: configuredBackendConfiguration?.baseURL))
                return
            }

            let device = GeminiLiveBackendDeviceContext.currentMac()
            let oauthFlow = Self.makePendingOAuthFlow(device: device)
            cancelPendingOAuthLogin()
            pendingOAuthFlow = oauthFlow
            setSaving(true)
            setAuthPhase(.signingIn)
            setLastError(nil)
            setStatus("Continue signing in from your browser...")

            _ = configuration
            let url = NotchWebPortal.oauthAuthorizeURL(
                clientID: oauthFlow.authorizationRequest.clientID,
                redirectURI: oauthFlow.authorizationRequest.redirectURI,
                state: oauthFlow.authorizationRequest.state,
                codeChallenge: oauthFlow.authorizationRequest.codeChallenge,
                identityProvider: "google",
                apiBaseURL: configuration.baseURL
            )
            NotchWebPortal.openInBrowser(url)
        }
    }

    func openWebProCheckout() {
        NotchWebPortal.openInBrowser(NotchWebPortal.proCheckoutURL(apiBaseURL: configuredBackendConfiguration?.baseURL))
    }

    func handleOAuthCallbackURL(_ url: URL) {
        Task {
            guard let activeOAuthFlow = pendingOAuthFlow else {
                setLastError("Browser sign-in expired. Please try again.")
                setStatus("Browser sign-in expired. Try again.")
                return
            }

            guard let configuration = await ensureResolvedConfigurationForAuth() else {
                cancelPendingOAuthLogin()
                setLastError("Gemini Live server URL is missing.")
                setStatus("Check the connection and try again.")
                return
            }

            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                cancelPendingOAuthLogin()
                applyAuthFailure(message: "Invalid OAuth callback.")
                setStatus("Couldn't finish browser sign-in.")
                return
            }

            let queryItems = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
                if result[item.name] == nil {
                    result[item.name] = item.value ?? ""
                }
            }

            if let error = queryItems["error"]?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                cancelPendingOAuthLogin()
                let description = queryItems["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                applyAuthFailure(message: description?.isEmpty == false ? description! : "Browser sign-in was cancelled.")
                setStatus("Browser sign-in was cancelled.")
                return
            }

            let returnedState = queryItems["state"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard returnedState == activeOAuthFlow.authorizationRequest.state else {
                cancelPendingOAuthLogin()
                applyAuthFailure(message: "Invalid OAuth state.")
                setStatus("Couldn't verify browser sign-in.")
                return
            }

            let code = queryItems["code"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else {
                cancelPendingOAuthLogin()
                applyAuthFailure(message: "Missing OAuth authorization code.")
                setStatus("Couldn't finish browser sign-in.")
                return
            }

            setSaving(true)
            setLastError(nil)
            setStatus("Finishing secure sign-in...")
            setAuthPhase(.signingIn)
            updatePublishedAuthState()

            do {
                let session = try await client.exchangeOAuthAuthorizationCode(
                    configuration: configuration,
                    code: code,
                    codeVerifier: activeOAuthFlow.codeVerifier,
                    authorizationRequest: activeOAuthFlow.authorizationRequest,
                    device: activeOAuthFlow.device
                )
                pendingOAuthFlow = nil
                storeBackendAuthSession(session)
                await refreshSubscriptionStatus()
                setStatus(nil)
            } catch {
                cancelPendingOAuthLogin()
                applyAuthFailure(error)
                setStatus("Couldn't finish browser sign-in.")
            }

            setSaving(false)
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
        cancelPendingOAuthLogin()
        authStore.delete()
        if let preservedEmail {
            authStore.saveLastEmail(preservedEmail)
        }
        storedAuthSession = nil
        setAuthPhase(.signedOut)
        updatePublishedAuthState()
        setProFromBackend(false)
        entitlementStore?.markSignedOut()
        onAuthChanged?()
    }

    func shouldClearBackendAuthSession(for error: Error) -> Bool {
        classifiedFailure(for: error)?.resetReason != nil
    }

    func shutdown() {
        authRefreshTask?.cancel()
        authRefreshTask = nil
        logoutRetryTask?.cancel()
        logoutRetryTask = nil
        cancelPendingOAuthLogin()
    }

    private var configuredBackendConfiguration: GeminiLiveBackendConfiguration? {
        currentConfigurationProvider?() ?? configStore.read()
    }

    private var configuredBackendConfigurationForAuth: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(baseURL: configuration.baseURL, clientToken: configuration.clientToken, userAccessToken: nil)
    }

    private var configuredBackendUserConfiguration: GeminiLiveBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration, let session = storedAuthSession else { return nil }
        return GeminiLiveBackendConfiguration(baseURL: configuration.baseURL, clientToken: nil, userAccessToken: session.accessToken)
    }

    private func ensureResolvedConfigurationForAuth() async -> GeminiLiveBackendConfiguration? {
        if let ensureConfigurationForAuth {
            return await ensureConfigurationForAuth()
        }
        return configuredBackendConfigurationForAuth
    }

    private func parsedISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
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

    private func shouldKeepUsingCurrentSession(_ session: GeminiLiveBackendAuthSession, forceRefresh: Bool) -> Bool {
        guard let accessExpiry = parsedISO8601Date(session.expiresAt) else { return false }
        return accessExpiry > Date() && !forceRefresh
    }

    private func prepareRefreshCandidate() -> GeminiLiveBackendAuthSession? {
        if let storedAuthSession { return storedAuthSession }
        guard let restoredSession = authStore.read() else {
            storedAuthSession = nil
            setAuthPhase(.signedOut)
            updatePublishedAuthState()
            return nil
        }
        storedAuthSession = restoredSession
        setAuthPhase(.authenticated(restoredSession))
        updatePublishedAuthState()
        return restoredSession
    }

    private func refreshRequestContext(
        for session: GeminiLiveBackendAuthSession,
        forceRefresh: Bool
    ) -> (refreshToken: String, configuration: GeminiLiveBackendConfiguration)? {
        guard let refreshToken = session.refreshToken,
              !refreshToken.isEmpty,
              let configuration = configuredBackendConfigurationForAuth else {
            if shouldKeepUsingCurrentSession(session, forceRefresh: forceRefresh) {
                return nil
            }
            clearBackendAuthSession()
            return nil
        }
        return (refreshToken, configuration)
    }

    private func beginRefreshFlow(for session: GeminiLiveBackendAuthSession) {
        setAuthPhase(.refreshing(session))
        updatePublishedAuthState()
    }

    private func executeRefreshTask(
        configuration: GeminiLiveBackendConfiguration,
        refreshToken: String
    ) -> Task<GeminiLiveBackendAuthSession, Error> {
        Task { [client] in
            try await client.refresh(
                configuration: configuration,
                refreshToken: refreshToken,
                device: .currentMac(trustDevice: false)
            )
        }
    }

    private func handleRefreshError(
        _ error: Error,
        fallback session: GeminiLiveBackendAuthSession,
        forceRefresh: Bool
    ) -> GeminiLiveBackendAuthSession? {
        if shouldClearBackendAuthSession(for: error) {
            clearBackendAuthSession()
            return nil
        }
        if shouldKeepUsingCurrentSession(session, forceRefresh: forceRefresh) {
            setAuthPhase(.authenticated(session))
            updatePublishedAuthState()
            return session
        }
        applyAuthFailure(error)
        return nil
    }

    private func awaitRefreshTask(
        _ task: Task<GeminiLiveBackendAuthSession, Error>,
        fallback session: GeminiLiveBackendAuthSession,
        forceRefresh: Bool,
        shouldStoreResult: Bool
    ) async -> GeminiLiveBackendAuthSession? {
        do {
            let refreshedSession = try await task.value
            if shouldStoreResult {
                storeBackendAuthSession(refreshedSession)
            }
            return refreshedSession
        } catch {
            return handleRefreshError(error, fallback: session, forceRefresh: forceRefresh)
        }
    }

    private func runRefresh(
        for session: GeminiLiveBackendAuthSession,
        forceRefresh: Bool
    ) async -> GeminiLiveBackendAuthSession? {
        guard let context = refreshRequestContext(for: session, forceRefresh: forceRefresh) else {
            return shouldKeepUsingCurrentSession(session, forceRefresh: forceRefresh) ? session : nil
        }

        beginRefreshFlow(for: session)

        if let authRefreshTask {
            return await awaitRefreshTask(authRefreshTask, fallback: session, forceRefresh: forceRefresh, shouldStoreResult: true)
        }

        let task = executeRefreshTask(configuration: context.configuration, refreshToken: context.refreshToken)
        authRefreshTask = task
        defer { authRefreshTask = nil }
        return await awaitRefreshTask(task, fallback: session, forceRefresh: forceRefresh, shouldStoreResult: true)
    }

    private func refreshBackendAuthSessionIfNeeded(forceRefresh: Bool = false) async -> GeminiLiveBackendAuthSession? {
        guard let session = prepareRefreshCandidate() else { return nil }

        if backendRefreshTokenExpired(session) {
            clearBackendAuthSession()
            return nil
        }

        if !forceRefresh && !backendAccessTokenNeedsRefresh(session) {
            return session
        }

        return await runRefresh(for: session, forceRefresh: forceRefresh)
    }

    private func loadCurrentAuth() {
        storedAuthSession = authStore.read()
        if let session = storedAuthSession {
            setAuthPhase(.authenticated(session))
        } else {
            setAuthPhase(.signedOut)
        }
        updatePublishedAuthState()
        if let user = storedAuthSession?.user {
            applyEntitlement(from: user)
        } else {
            setProFromBackend(false)
            entitlementStore?.markSignedOut()
        }
    }

    private func setAuthPhase(_ phase: BackendAuthPhase) {
        authPhase = phase
    }

    private func classifiedFailure(for error: Error) -> (message: String, resetReason: BackendAuthResetReason?)? {
        if let backendError = error as? GeminiLiveBackendError {
            switch backendError {
            case .unauthorized:
                return (backendError.errorDescription ?? error.localizedDescription, .unauthorized)
            case let .server(message):
                return (message, authResetReason(for: message))
            default:
                return (backendError.errorDescription ?? error.localizedDescription, nil)
            }
        }

        let message = error.localizedDescription
        let resetReason = authResetReason(for: message)
        return message.isEmpty ? nil : (message, resetReason)
    }

    private func authFailure(for error: Error) -> BackendAuthFailure {
        guard let failure = classifiedFailure(for: error) else {
            return .other(message: error.localizedDescription)
        }
        if failure.resetReason == .unauthorized { return .unauthorized }
        if let resetReason = failure.resetReason {
            return .server(message: failure.message, resetReason: resetReason)
        }
        return .other(message: failure.message)
    }

    private func applyAuthFailure(_ error: Error) {
        setAuthPhase(.failed(authFailure(for: error)))
        setLastError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        updatePublishedAuthState()
    }

    private func applyAuthFailure(message: String) {
        setAuthPhase(.failed(.other(message: message)))
        setLastError(message)
        updatePublishedAuthState()
    }

    private func authResetReason(for message: String) -> BackendAuthResetReason? {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("invalid refresh token") || normalized.contains("refresh token expired") {
            return .invalidRefreshToken
        }
        if normalized.contains("jwt expired") || normalized.contains("token has expired") || normalized.contains("token expired") || normalized.contains("expired session") || normalized.contains("expired token") {
            return .expiredSession
        }
        if normalized.contains("invalid or expired session token") || normalized.contains("invalid session") || normalized.contains("session token") || normalized.contains("invalid token") {
            return .invalidSession
        }
        if normalized.contains("unauthorized") {
            return .unauthorized
        }
        return nil
    }

    private func storeBackendAuthSession(_ session: GeminiLiveBackendAuthSession) {
        cancelPendingOAuthLogin(resetSaving: false)
        _ = authStore.save(session)
        storedAuthSession = session
        authStore.saveLastEmail(session.user.email)
        onAuthEmailChange?(session.user.email)
        setLastError(nil)
        setAuthPhase(.authenticated(session))
        updatePublishedAuthState()
        applyEntitlement(from: session.user)
        onAuthChanged?()
    }

    private func updatePublishedAuthState() {
        switch authPhase {
        case let .authenticated(session), let .refreshing(session):
            authenticatedEmail = session.user.email
            signedInSummary = session.user.email
            isAuthenticated = true
        case .signingIn, .failed, .signedOut:
            authenticatedEmail = storedAuthSession?.user.email
            signedInSummary = storedAuthSession?.user.email
            isAuthenticated = storedAuthSession != nil
        }
    }

    private func syncAuthenticatedUser(_ user: GeminiLiveBackendAuthUser) {
        guard let existingSession = storedAuthSession else {
            applyEntitlement(from: user)
            return
        }

        let updatedSession = GeminiLiveBackendAuthSession(
            accessToken: existingSession.accessToken,
            expiresAt: existingSession.expiresAt,
            refreshToken: existingSession.refreshToken,
            refreshExpiresAt: existingSession.refreshExpiresAt,
            user: user
        )

        storedAuthSession = updatedSession
        _ = authStore.save(updatedSession)

        switch authPhase {
        case .authenticated, .refreshing:
            setAuthPhase(.authenticated(updatedSession))
        case .signingIn, .failed, .signedOut:
            break
        }

        updatePublishedAuthState()
        applyEntitlement(from: user)
    }

    private func applyEntitlement(from user: GeminiLiveBackendAuthUser) {
        let isPro = user.isPro ?? false
        setProFromBackend(isPro)
        entitlementStore?.updateBackendEntitlement(
            isPro: isPro,
            accountID: user.id,
            accountEmail: user.email,
            permissionPolicy: user.permissionPolicy
        )
    }

    private func setProFromBackend(_ newValue: Bool) {
        let didChange = isProFromBackend != newValue
        isProFromBackend = newValue
        if didChange { onProChanged?(newValue) }
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

    private func cancelPendingOAuthLogin(resetSaving: Bool = true) {
        pendingOAuthFlow = nil
        if resetSaving { setSaving(false) }
    }

    private struct PendingOAuthFlow {
        let authorizationRequest: GeminiLiveBackendOAuthAuthorizationRequest
        let codeVerifier: String
        let device: GeminiLiveBackendDeviceContext
    }

    private static func makePendingOAuthFlow(device: GeminiLiveBackendDeviceContext) -> PendingOAuthFlow {
        let state = randomBase64URLString(byteCount: 32)
        let codeVerifier = randomBase64URLString(byteCount: 48)
        let challengeData = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        let codeChallenge = challengeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return PendingOAuthFlow(
            authorizationRequest: GeminiLiveBackendOAuthAuthorizationRequest(state: state, codeChallenge: codeChallenge),
            codeVerifier: codeVerifier,
            device: device
        )
    }

    private static func randomBase64URLString(byteCount: Int) -> String {
        let bytes = (0 ..< byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
