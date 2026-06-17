import CryptoKit
import Foundation

// Single account authority shared by Portal-backed app features.

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
    case authenticated(PortalAuthSession)
    case refreshing(PortalAuthSession)
    case failed(BackendAuthFailure)
}

@MainActor
final class PortalAccountCoordinator: ObservableObject {
    @Published private(set) var authPhase: BackendAuthPhase = .signedOut
    @Published private(set) var isAuthenticated = false
    @Published private(set) var signedInSummary: String?
    @Published private(set) var authenticatedEmail: String?
    @Published private(set) var avatarURL: URL?
    @Published private(set) var isProFromBackend = false
    @Published private(set) var lastError: String?

    private let client: PortalAPIClient
    private let configStore: PortalConfigurationStore
    private let authStore: PortalAuthStore
    private let entitlementStore: NotchEntitlementStore?
    private var storedAuthSession: PortalAuthSession?
    private var authRefreshTask: Task<PortalAuthSession, Error>?
    private var logoutRetryTask: Task<Void, Never>?
    private var pendingOAuthFlows: [String: PendingOAuthFlow] = [:]

    var onAuthChanged: (@MainActor () -> Void)?
    var onProChanged: (@MainActor (Bool) -> Void)?
    var onStatusChange: (@MainActor (String?) -> Void)?
    var onErrorChange: (@MainActor (String?) -> Void)?
    var onSavingStateChange: (@MainActor (Bool) -> Void)?
    var onAuthEmailChange: (@MainActor (String) -> Void)?
    var currentDraftEmailProvider: (@MainActor () -> String?)?
    var shouldDisconnectManagedSession: (@MainActor () -> Bool)?
    var disconnectManagedSession: (@MainActor () -> Void)?

    init(
        client: PortalAPIClient,
        configStore: PortalConfigurationStore,
        authStore: PortalAuthStore,
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

    var portalBaseURL: URL? {
        configuredBackendConfiguration?.baseURL
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

    private var currentAuthSession: PortalAuthSession? {
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
        guard let configuration = await freshConfiguredPortalUserConfiguration(forceRefresh: forceRefresh) else {
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

            let device = PortalDeviceContext.currentMac()
            let oauthFlow = Self.makePendingOAuthFlow(device: device)
            pendingOAuthFlows[oauthFlow.authorizationRequest.state] = oauthFlow
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
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                cancelPendingOAuthLogin()
                applyAuthFailure(message: Localization.get("Invalid OAuth callback."))
                setStatus("Couldn't finish browser sign-in.")
                return
            }

            let queryItems = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
                if result[item.name] == nil {
                    result[item.name] = item.value ?? ""
                }
            }

            let returnedState = queryItems["state"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let activeOAuthFlow = pendingOAuthFlows[returnedState] else {
                setLastError("Browser sign-in expired. Please try again.")
                setStatus("Browser sign-in expired. Try again.")
                return
            }

            guard let configuration = await ensureResolvedConfigurationForAuth() else {
                pendingOAuthFlows.removeValue(forKey: returnedState)
                if pendingOAuthFlows.isEmpty { setSaving(false) }
                setLastError("Gemini Live server URL is missing.")
                setStatus("Check the connection and try again.")
                return
            }

            if let error = queryItems["error"]?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                pendingOAuthFlows.removeValue(forKey: returnedState)
                if pendingOAuthFlows.isEmpty { setSaving(false) }
                let description = queryItems["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                applyAuthFailure(message: description?.isEmpty == false ? description! : Localization.get("Browser sign-in was cancelled."))
                setStatus("Browser sign-in was cancelled.")
                return
            }

            let code = queryItems["code"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else {
                pendingOAuthFlows.removeValue(forKey: returnedState)
                if pendingOAuthFlows.isEmpty { setSaving(false) }
                applyAuthFailure(message: Localization.get("Missing OAuth authorization code."))
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
                pendingOAuthFlows.removeValue(forKey: returnedState)
                storeBackendAuthSession(session)
                await refreshSubscriptionStatus()
                setStatus(nil)
            } catch {
                pendingOAuthFlows.removeValue(forKey: returnedState)
                applyAuthFailure(error)
                setStatus("Couldn't finish browser sign-in.")
            }

            if pendingOAuthFlows.isEmpty {
                setSaving(false)
            }
        }
    }

    func reloadCurrentAuth() {
        loadCurrentAuth()
    }

    func freshConfiguredPortalUserConfiguration(forceRefresh: Bool = false) async -> PortalBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration,
              let session = await refreshBackendAuthSessionIfNeeded(forceRefresh: forceRefresh) else {
            return nil
        }

        return PortalBackendConfiguration(
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

    private var configuredBackendConfiguration: PortalBackendConfiguration? {
        configStore.read()
    }

    private var configuredBackendConfigurationForAuth: PortalBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration else { return nil }
        return PortalBackendConfiguration(baseURL: configuration.baseURL, clientToken: configuration.clientToken, userAccessToken: nil)
    }

    private var configuredBackendUserConfiguration: PortalBackendConfiguration? {
        guard let configuration = configuredBackendConfiguration, let session = storedAuthSession else { return nil }
        return PortalBackendConfiguration(baseURL: configuration.baseURL, clientToken: nil, userAccessToken: session.accessToken)
    }

    private func ensureResolvedConfigurationForAuth() async -> PortalBackendConfiguration? {
        if let configuration = configuredBackendConfigurationForAuth {
            return configuration
        }
        guard configStore.save(baseURLString: PortalHostedBackend.defaultURL, clientToken: nil) else {
            return nil
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

    private func backendAccessTokenNeedsRefresh(_ session: PortalAuthSession) -> Bool {
        guard let expiresAt = parsedISO8601Date(session.expiresAt) else { return true }
        return expiresAt <= Date().addingTimeInterval(5 * 60)
    }

    private func backendRefreshTokenExpired(_ session: PortalAuthSession) -> Bool {
        guard let refreshExpiresAt = session.refreshExpiresAt else { return false }
        guard let expiresAt = parsedISO8601Date(refreshExpiresAt) else { return true }
        return expiresAt <= Date()
    }

    private func shouldKeepUsingCurrentSession(_ session: PortalAuthSession, forceRefresh: Bool) -> Bool {
        guard let accessExpiry = parsedISO8601Date(session.expiresAt) else { return false }
        return accessExpiry > Date() && !forceRefresh
    }

    private func prepareRefreshCandidate() -> PortalAuthSession? {
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
        for session: PortalAuthSession,
        forceRefresh: Bool
    ) -> (refreshToken: String, configuration: PortalBackendConfiguration)? {
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

    private func beginRefreshFlow(for session: PortalAuthSession) {
        setAuthPhase(.refreshing(session))
        updatePublishedAuthState()
    }

    private func executeRefreshTask(
        configuration: PortalBackendConfiguration,
        refreshToken: String
    ) -> Task<PortalAuthSession, Error> {
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
        fallback session: PortalAuthSession,
        forceRefresh: Bool
    ) -> PortalAuthSession? {
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
        _ task: Task<PortalAuthSession, Error>,
        fallback session: PortalAuthSession,
        forceRefresh: Bool,
        shouldStoreResult: Bool
    ) async -> PortalAuthSession? {
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
        for session: PortalAuthSession,
        forceRefresh: Bool
    ) async -> PortalAuthSession? {
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

    private func refreshBackendAuthSessionIfNeeded(forceRefresh: Bool = false) async -> PortalAuthSession? {
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
        if let backendError = error as? PortalAPIError {
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

    private func storeBackendAuthSession(_ session: PortalAuthSession) {
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

    private func normalizedAvatarURL(from value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func updatePublishedAuthState() {
        switch authPhase {
        case let .authenticated(session), let .refreshing(session):
            authenticatedEmail = session.user.email
            signedInSummary = session.user.email
            avatarURL = normalizedAvatarURL(from: session.user.avatarURLString)
            isAuthenticated = true
        case .signingIn, .failed, .signedOut:
            authenticatedEmail = storedAuthSession?.user.email
            signedInSummary = storedAuthSession?.user.email
            avatarURL = normalizedAvatarURL(from: storedAuthSession?.user.avatarURLString)
            isAuthenticated = storedAuthSession != nil
        }
    }

    private func syncAuthenticatedUser(_ user: PortalAuthUser) {
        guard let existingSession = storedAuthSession else {
            applyEntitlement(from: user)
            return
        }

        let updatedSession = PortalAuthSession(
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

    private func applyEntitlement(from user: PortalAuthUser) {
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
        pendingOAuthFlows.removeAll()
        if resetSaving { setSaving(false) }
    }

    private struct PendingOAuthFlow {
        let authorizationRequest: PortalOAuthAuthorizationRequest
        let codeVerifier: String
        let device: PortalDeviceContext
    }

    private static func makePendingOAuthFlow(device: PortalDeviceContext) -> PendingOAuthFlow {
        let state = randomBase64URLString(byteCount: 32)
        let codeVerifier = randomBase64URLString(byteCount: 48)
        let challengeData = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        let codeChallenge = challengeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return PendingOAuthFlow(
            authorizationRequest: PortalOAuthAuthorizationRequest(state: state, codeChallenge: codeChallenge),
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
