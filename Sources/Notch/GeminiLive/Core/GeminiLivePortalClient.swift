import Foundation

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

    var expireDate: Date? {
        guard let expireTime else { return nil }
        return ISO8601DateFormatter().date(from: expireTime)
    }
}

struct GeminiLiveSessionTokenRequest: Encodable, Sendable {
    let model: String
    let systemInstruction: String?
    let voiceName: String?
    let thinkingLevel: String?
    let thinkingBudget: Int?
    let mediaResolution: String?
    let responseModalities: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case systemInstruction = "system_instruction"
        case voiceName = "voice_name"
        case thinkingLevel = "thinking_level"
        case thinkingBudget = "thinking_budget"
        case mediaResolution = "media_resolution"
        case responseModalities = "response_modalities"
    }
}

protocol GeminiLivePortalClient: AnyObject, Sendable {
    func geminiLiveHealth(configuration: PortalBackendConfiguration) async throws
    func createGeminiLiveSessionToken(
        configuration: PortalBackendConfiguration,
        request body: GeminiLiveSessionTokenRequest
    ) async throws -> GeminiLiveEphemeralTokenResponse
    func listGeminiLiveModels(configuration: PortalBackendConfiguration) async throws -> [GeminiLiveModel]
}

extension PortalAPIClient: GeminiLivePortalClient {}
