import Foundation

public enum GeminiThinkingLevel: String, CaseIterable, Codable, Sendable {
    case minimal = "Minimal"
    case off = "Off"
    case automatic = "Auto"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    public static func availableLevels(forModel modelID: String) -> [GeminiThinkingLevel] {
        if modelUsesThinkingLevel(modelID) {
            return [.minimal, .low, .medium, .high]
        }
        return [.off, .automatic, .low, .medium, .high]
    }

    public func normalized(forModel modelID: String) -> GeminiThinkingLevel {
        if Self.modelUsesThinkingLevel(modelID) {
            switch self {
            case .off, .automatic:
                return .minimal
            case .minimal, .low, .medium, .high:
                return self
            }
        }

        switch self {
        case .minimal:
            return .off
        case .off, .automatic, .low, .medium, .high:
            return self
        }
    }

    public func wireConfiguration(forModel modelID: String) -> GeminiThinkingWireConfiguration {
        let normalized = normalized(forModel: modelID)
        if Self.modelUsesThinkingLevel(modelID) {
            return .level(normalized.apiLevelName)
        }

        switch normalized {
        case .off:
            return .budget(0)
        case .automatic:
            return .automatic
        case .low:
            return .budget(512)
        case .medium:
            return .budget(2048)
        case .high:
            return .budget(8192)
        case .minimal:
            return .budget(0)
        }
    }

    public static func modelUsesThinkingLevel(_ modelID: String) -> Bool {
        let normalized = modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
            .lowercased()
        return normalized.hasPrefix("gemini-3")
    }

    private var apiLevelName: String {
        switch self {
        case .minimal:
            return "MINIMAL"
        case .low:
            return "LOW"
        case .medium:
            return "MEDIUM"
        case .high:
            return "HIGH"
        case .off, .automatic:
            return "MINIMAL"
        }
    }
}

public enum GeminiThinkingWireConfiguration: Equatable, Sendable {
    case level(String)
    case budget(Int)
    case automatic
}

public struct GeminiLiveResumptionState: Equatable, Sendable {
    public private(set) var handle: String?

    public init(handle: String? = nil) {
        self.handle = handle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? handle
            : nil
    }

    public mutating func acceptUpdate(resumable: Bool, newHandle: String?) {
        guard resumable,
              let newHandle,
              !newHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        handle = newHandle
    }

    public mutating func clear() {
        handle = nil
    }
}
