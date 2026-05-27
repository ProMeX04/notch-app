import Foundation

protocol GeminiLiveUserAPIClient: AnyObject, Sendable {
    func validateAPIKey(_ apiKey: String) async throws
    func fetchAvailableLiveModels(apiKey: String) async throws -> [GeminiLiveModel]
}

final class URLSessionGeminiLiveUserAPIClient: GeminiLiveUserAPIClient {
    private let urlSession: URLSession
    private let jsonDecoder = JSONDecoder()

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func validateAPIKey(_ apiKey: String) async throws {
        let request = try makeModelsRequest(apiKey: apiKey, pageSize: nil, timeout: 15)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIKeyValidationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let apiError = try? jsonDecoder.decode(GeminiAPIErrorEnvelope.self, from: data),
               !apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiAPIKeyValidationError.server(apiError.error.message)
            }
            throw GeminiAPIKeyValidationError.server("Gemini returned HTTP \(httpResponse.statusCode) while testing the API key.")
        }
    }

    func fetchAvailableLiveModels(apiKey: String) async throws -> [GeminiLiveModel] {
        let request = try makeModelsRequest(apiKey: apiKey, pageSize: "1000", timeout: 20)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIKeyValidationError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let apiError = try? jsonDecoder.decode(GeminiAPIErrorEnvelope.self, from: data),
               !apiError.error.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiAPIKeyValidationError.server(apiError.error.message)
            }
            throw GeminiAPIKeyValidationError.server("Gemini returned HTTP \(httpResponse.statusCode) while updating models.")
        }

        let payload = try jsonDecoder.decode(GeminiModelListEnvelope.self, from: data)
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

    private func makeModelsRequest(apiKey: String, pageSize: String?, timeout: TimeInterval) throws -> URLRequest {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }
        var queryItems = [URLQueryItem(name: "key", value: apiKey)]
        if let pageSize {
            queryItems.append(URLQueryItem(name: "pageSize", value: pageSize))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw GeminiAPIKeyValidationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return request
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
}

enum GeminiAPIKeyValidationError: LocalizedError {
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
