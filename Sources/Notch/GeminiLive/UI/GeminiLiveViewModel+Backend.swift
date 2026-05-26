import Foundation

extension GeminiLiveViewModel {
    func openWebAccountSignup() {
        NotchWebPortal.openInBrowser(NotchWebPortal.signupURL(apiBaseURL: configuredBackendConfiguration?.baseURL))
    }

    func openWebAccountLogin() {
        backend.openWebAccountLogin()
    }

    func handleBackendOAuthCallback(_ url: URL) {
        backend.handleOAuthCallbackURL(url)
    }

    func openWebProCheckout() {
        backend.openWebProCheckout()
    }

    func refreshBackendSubscriptionStatus(forceRefresh: Bool = false) async {
        await backend.refreshSubscriptionStatus(forceRefresh: forceRefresh)
    }

    var hasConfiguredAPIKey: Bool {
        hasConfiguredConnection
    }

    var hasConfiguredConnection: Bool {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return configuredAPIKey != nil
        case .managedServer:
            return configuredBackendConfiguration != nil && isBackendAuthenticated
        }
    }

    var requiresAuthenticationForCurrentConnection: Bool {
        selectedConnectionMethod == .managedServer
            && configuredBackendConfiguration != nil
            && !isBackendAuthenticated
    }

    var isBackendAuthRefreshing: Bool {
        backend.isAuthRefreshInFlight
    }

    var backendAuthFailureMessage: String? {
        backend.authPhaseDescription
    }

    var requiresProForCurrentConnection: Bool {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return !talkPermissionDecision.isAllowed
        case .managedServer:
            return isBackendAuthenticated && !talkPermissionDecision.isAllowed
        }
    }

    var canStartConnection: Bool {
        hasConfiguredConnection && !requiresProForCurrentConnection
    }

    var selectedConnectionSetupTitle: String {
        selectedConnectionMethod.setupTitle
    }

    var selectedConnectionSetupDescription: String {
        switch selectedConnectionMethod {
        case .userAPIKey:
            return selectedConnectionMethod.setupDescription
        case .managedServer:
            if configuredBackendConfiguration == nil {
                return "Configure the backend URL first in the Settings tab."
            }
            if requiresAuthenticationForCurrentConnection {
                return "Sign in to your server account in the Settings tab."
            }
            if !talkPermissionDecision.isAllowed {
                return talkPermissionDecision.message
            }
            return "Ready to use your server-managed Gemini session."
        }
    }

    var selectedConnectionManageButtonTitle: String {
        selectedConnectionMethod.manageButtonTitle
    }

    var defaultDisconnectedStatusText: String {
        if requiresAuthenticationForCurrentConnection {
            return "Sign in to your Gemini Live server account."
        }
        if requiresProForCurrentConnection {
            return talkPermissionDecision.message
        }
        return hasConfiguredConnection ? "Ready to connect to Gemini Live." : selectedConnectionMethod.setupDescription
    }

    func saveBackendConfiguration() async -> Bool {
        guard let draftBackendURL else {
            lastErrorMessage = "Gemini Live server URL is missing."
            statusText = "Enter the Gemini Live server URL, then save again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Testing Gemini Live server..."
        defer { isSavingAPIKey = false }

        do {
            guard
                let normalizedURL = URL(string: draftBackendURL),
                let scheme = normalizedURL.scheme,
                !scheme.isEmpty,
                normalizedURL.host != nil
            else {
                throw GeminiLiveBackendError.invalidBaseURL
            }

            let normalizedConfiguration = GeminiLiveBackendConfiguration(
                baseURL: normalizedURL.path.isEmpty ? normalizedURL.appendingPathComponent("") : normalizedURL,
                clientToken: draftBackendClientToken,
                userAccessToken: backend.currentAccessToken
            )
            do {
                try await backendClient.validate(configuration: normalizedConfiguration)
            } catch GeminiLiveBackendError.unauthorized {
                guard backendConfigStore.save(
                    baseURLString: normalizedConfiguration.displayURL,
                    clientToken: normalizedConfiguration.clientToken
                ) else {
                    lastErrorMessage = "Couldn't save the Gemini Live server configuration."
                    statusText = "Gemini Live server validation passed, but saving failed."
                    return false
                }

                storedBackendConfiguration = GeminiLiveBackendConfiguration(
                    baseURL: normalizedConfiguration.baseURL,
                    clientToken: normalizedConfiguration.clientToken,
                    userAccessToken: nil
                )
                backendURLText = normalizedConfiguration.displayURL
                backendClientTokenText = normalizedConfiguration.clientToken ?? ""
                lastErrorMessage = nil
                statusText = "Gemini Live server saved. Sign in to continue."
                syncConfiguredConnectionState()
                return true
            }

            guard backendConfigStore.save(
                baseURLString: normalizedConfiguration.displayURL,
                clientToken: normalizedConfiguration.clientToken
            ) else {
                lastErrorMessage = "Couldn't save the Gemini Live server configuration."
                statusText = "Gemini Live server validation passed, but saving failed."
                return false
            }

            storedBackendConfiguration = normalizedConfiguration
            backendURLText = normalizedConfiguration.displayURL
            backendClientTokenText = normalizedConfiguration.clientToken ?? ""
            lastErrorMessage = nil
            statusText = "Gemini Live server saved."
            syncConfiguredConnectionState()
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Gemini Live server test failed."
            return false
        }
    }

    func saveAPIKey() async -> Bool {
        guard let draftAPIKey else {
            lastErrorMessage = "Gemini API key is missing."
            statusText = "Enter your Gemini API key, then save again."
            return false
        }

        isSavingAPIKey = true
        lastErrorMessage = nil
        statusText = "Testing Gemini API key..."
        defer { isSavingAPIKey = false }

        do {
            try await validateAPIKey(draftAPIKey)

            guard keyStore.save(draftAPIKey) else {
                lastErrorMessage = keyStore.saveFailureMessage
                statusText = "Gemini API key test passed, but saving failed."
                return false
            }

            storedAPIKey = draftAPIKey
            apiKeyText = draftAPIKey
            lastErrorMessage = nil
            statusText = keyStore.saveSuccessMessage
            syncConfiguredConnectionState()
            return true
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Gemini API key test failed."
            return false
        }
    }

    func refreshLiveModelsOnLaunchIfPossible() async {
        switch selectedConnectionMethod {
        case .userAPIKey:
            guard configuredAPIKey != nil else { return }
        case .managedServer:
            guard configuredBackendConfiguration != nil, isBackendAuthenticated else { return }
        }
        await refreshAvailableLiveModels(silent: true)
    }

    @discardableResult
    func refreshAvailableLiveModels(silent: Bool = false) async -> Bool {
        isRefreshingLiveModels = true
        if !silent {
            lastErrorMessage = nil
            statusText = "Updating Gemini Live models..."
        }
        defer { isRefreshingLiveModels = false }

        let models: [GeminiLiveModel]
        do {
            switch selectedConnectionMethod {
            case .userAPIKey:
                guard let apiKey = configuredAPIKey else {
                    lastLiveModelRefreshMessage = "Gemini API key is missing."
                    if !silent {
                        lastErrorMessage = "Gemini API key is missing."
                        statusText = "Save your Gemini API key before updating models."
                    }
                    return false
                }
                models = try await fetchAvailableLiveModels(apiKey: apiKey)

            case .managedServer:
                guard configuredBackendConfiguration != nil else {
                    lastLiveModelRefreshMessage = "Gemini Live server is missing."
                    if !silent {
                        lastErrorMessage = "Gemini Live server is missing."
                        statusText = "Save your Gemini Live server before updating models."
                    }
                    return false
                }
                guard let backendConfiguration = await backend.freshConfiguredBackendUserConfiguration() else {
                    lastLiveModelRefreshMessage = "Sign in to your Gemini Live server account before updating models."
                    if !silent {
                        lastErrorMessage = "Sign in to your Gemini Live server account before updating models."
                        statusText = "Sign in to your Gemini Live server account."
                    }
                    return false
                }
                models = try await backendClient.listLiveModels(configuration: backendConfiguration)
            }

            guard !models.isEmpty else {
                lastLiveModelRefreshMessage = "No Gemini Live models were returned."
                if !silent {
                    lastErrorMessage = "No Gemini Live models were returned."
                    statusText = "Gemini Live model update found no supported models."
                }
                return false
            }

            availableLiveModels = models
            if !models.contains(where: { $0.apiName == selectedModelID }) {
                selectedModel = models[0]
            }

            lastLiveModelRefreshMessage = nil
            if !silent {
                lastErrorMessage = nil
                statusText = "Updated \(models.count) Gemini Live models."
            }
            return true
        } catch {
            if backend.shouldClearBackendAuthSession(for: error) {
                backend.clearBackendAuthSession()
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastLiveModelRefreshMessage = message
            if !silent {
                lastErrorMessage = message
                statusText = "Gemini Live model update failed."
            }
            return false
        }
    }

    func logoutBackendAccount() async {
        await backend.logout()
        backendAuthPasswordText = ""
    }

    var draftBackendURL: String? {
        let trimmedInput = backendURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    var draftBackendAuthEmail: String? {
        let trimmedInput = backendAuthEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    var draftBackendAuthPassword: String? {
        let trimmedInput = backendAuthPasswordText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    var draftAPIKey: String? {
        let trimmedInput = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    var draftBackendClientToken: String? {
        let trimmedInput = backendClientTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedInput.isEmpty ? nil : trimmedInput
    }

    var configuredBackendConfiguration: GeminiLiveBackendConfiguration? {
        storedBackendConfiguration ?? backendConfigStore.read()
    }

    var needsBackendConfigurationSave: Bool {
        guard let draftBackendURL else { return configuredBackendConfiguration == nil }
        guard let configuration = configuredBackendConfiguration else { return true }

        return configuration.displayURL != draftBackendURL
            || configuration.clientToken != draftBackendClientToken
    }

    var configuredAPIKey: String? {
        currentStoredGeminiKey()
    }

    func currentStoredGeminiKey() -> String? {
        normalizedStoredSecret(storedAPIKey ?? keyStore.read())
    }

    func syncConfiguredConnectionState(updateStatus: Bool = false) {
        hasSavedAPIKey = hasConfiguredConnection
        guard updateStatus else { return }
        statusText = defaultDisconnectedStatusText
    }

    func ensureBackendConfigurationForAuth() async -> GeminiLiveBackendConfiguration? {
        backendURLText = GeminiLiveHostedBackend.defaultURL
        backendClientTokenText = ""

        if needsBackendConfigurationSave {
            let didSave = await saveBackendConfiguration()
            guard didSave else { return nil }
        }

        guard let configuration = configuredBackendConfiguration else { return nil }
        return GeminiLiveBackendConfiguration(
            baseURL: configuration.baseURL,
            clientToken: configuration.clientToken,
            userAccessToken: nil
        )
    }

    func normalizedStoredSecret(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func validateAPIKey(_ apiKey: String) async throws {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
        ]

        guard let url = components.url else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIKeyValidationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data),
               !apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiAPIKeyValidationError.server(apiError.error.message)
            }
            throw GeminiAPIKeyValidationError.server("Gemini returned HTTP \(httpResponse.statusCode) while testing the API key.")
        }
    }

    private func fetchAvailableLiveModels(apiKey: String) async throws -> [GeminiLiveModel] {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "1000"),
        ]

        guard let url = components.url else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIKeyValidationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data),
               !apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiAPIKeyValidationError.server(apiError.error.message)
            }
            throw GeminiAPIKeyValidationError.server("Gemini returned HTTP \(httpResponse.statusCode) while updating models.")
        }

        let payload = try JSONDecoder().decode(GeminiModelListEnvelope.self, from: data)
        return payload.models
            .filter { model in
                (model.supportedGenerationMethods ?? []).contains { method in
                    method.caseInsensitiveCompare("bidiGenerateContent") == .orderedSame
                }
            }
            .map { model in
                GeminiLiveModel(
                    id: model.name,
                    name: model.name,
                    displayName: model.displayName,
                    supportedGenerationMethods: model.supportedGenerationMethods ?? []
                )
            }
            .sorted { lhs, rhs in
                if lhs.apiName.contains("latest") != rhs.apiName.contains("latest") {
                    return lhs.apiName.contains("latest")
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private struct GeminiAPIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    private struct GeminiModelListEnvelope: Decodable {
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]?
        }

        let models: [Model]
    }

    private enum GeminiAPIKeyValidationError: LocalizedError {
        case invalidRequest
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Couldn't prepare the Gemini API key test."
            case .invalidResponse:
                return "Gemini returned an invalid response while testing the API key."
            case let .server(message):
                return message
            }
        }
    }
}
