import Foundation
import Security

final class GeminiLiveAPIKeyStore {
    private enum StorageMode {
        case developmentFile
        case keychain
    }

    private let mode: StorageMode
    private let keychainStore = GeminiLiveKeychainStore()
    private let developmentFileStore = GeminiLiveDevelopmentFileStore()

    init(processInfo: ProcessInfo) {
        let env = processInfo.environment
        if let override = env["NOTCH_DEV_PLAINTEXT_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            mode = override == "0" ? .keychain : .developmentFile
            return
        }

#if DEBUG
        mode = .developmentFile
#else
        mode = .keychain
#endif
    }

    var saveSuccessMessage: String {
        switch mode {
        case .developmentFile:
            return "API Key saved in development storage."
        case .keychain:
            return "API Key saved securely."
        }
    }

    var saveFailureMessage: String {
        switch mode {
        case .developmentFile:
            return "Gemini API key test passed, but saving to development storage failed."
        case .keychain:
            return "Gemini API key test passed, but saving to Keychain failed."
        }
    }

    func read() -> String? {
        switch mode {
        case .developmentFile:
            return developmentFileStore.read()
        case .keychain:
            return keychainStore.read()
        }
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        switch mode {
        case .developmentFile:
            return developmentFileStore.save(value)
        case .keychain:
            return keychainStore.save(value)
        }
    }

    func delete() {
        switch mode {
        case .developmentFile:
            developmentFileStore.delete()
        case .keychain:
            keychainStore.delete()
        }
    }
}

struct GeminiLiveSettings {
    let isMicrophoneEnabled: Bool
    let showTranscriptOverlay: Bool
    let systemPromptPresets: [GeminiSystemPromptPreset]
    let selectedSystemPromptID: String
}

final class GeminiLiveSettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "dev.notch.gemini-live-settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func read() -> GeminiLiveSettings? {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        // Migration: seed per-preset fields from old global values if absent.
        let legacyTools = payload.legacyEnabledTools ?? GeminiTool.allCases.map(\.rawValue)
        let legacyVoice = payload.legacyVoice ?? GeminiVoice.kore.rawValue
        let legacyThinking = payload.legacyThinkingLevel ?? GeminiThinkingLevel.off.rawValue

        let migratedPresets: [GeminiSystemPromptPreset] = (payload.systemPromptPresets ?? GeminiSystemPromptPreset.defaultPresets)
            .map { preset in
                var p = preset
                if p.enabledTools.isEmpty { p.enabledTools = legacyTools }
                if p.voice.isEmpty { p.voice = legacyVoice }
                if p.thinkingLevel.isEmpty { p.thinkingLevel = legacyThinking }
                return p
            }

        return GeminiLiveSettings(
            isMicrophoneEnabled: payload.isMicrophoneEnabled,
            showTranscriptOverlay: payload.showTranscriptOverlay,
            systemPromptPresets: migratedPresets,
            selectedSystemPromptID: payload.selectedSystemPromptID ?? GeminiSystemPromptPreset.defaultPreset.id
        )
    }

    func save(_ settings: GeminiLiveSettings) {
        let payload = Payload(
            isMicrophoneEnabled: settings.isMicrophoneEnabled,
            showTranscriptOverlay: settings.showTranscriptOverlay,
            systemPromptPresets: settings.systemPromptPresets,
            selectedSystemPromptID: settings.selectedSystemPromptID
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private struct Payload: Codable {
        let isMicrophoneEnabled: Bool
        let showTranscriptOverlay: Bool
        let systemPromptPresets: [GeminiSystemPromptPreset]?
        let selectedSystemPromptID: String?
        // Legacy fields — read only for migration, never written.
        let legacyEnabledTools: [String]?
        let legacyVoice: String?
        let legacyThinkingLevel: String?

        init(
            isMicrophoneEnabled: Bool,
            showTranscriptOverlay: Bool,
            systemPromptPresets: [GeminiSystemPromptPreset],
            selectedSystemPromptID: String
        ) {
            self.isMicrophoneEnabled = isMicrophoneEnabled
            self.showTranscriptOverlay = showTranscriptOverlay
            self.systemPromptPresets = systemPromptPresets
            self.selectedSystemPromptID = selectedSystemPromptID
            self.legacyEnabledTools = nil
            self.legacyVoice = nil
            self.legacyThinkingLevel = nil
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isMicrophoneEnabled, forKey: .isMicrophoneEnabled)
            try container.encode(showTranscriptOverlay, forKey: .showTranscriptOverlay)
            try container.encodeIfPresent(systemPromptPresets, forKey: .systemPromptPresets)
            try container.encodeIfPresent(selectedSystemPromptID, forKey: .selectedSystemPromptID)
            // Legacy fields intentionally not written.
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isMicrophoneEnabled = try container.decode(Bool.self, forKey: .isMicrophoneEnabled)
            showTranscriptOverlay = try container.decode(Bool.self, forKey: .showTranscriptOverlay)
            systemPromptPresets = try container.decodeIfPresent([GeminiSystemPromptPreset].self, forKey: .systemPromptPresets)
            selectedSystemPromptID = try container.decodeIfPresent(String.self, forKey: .selectedSystemPromptID)
            legacyEnabledTools = try container.decodeIfPresent([String].self, forKey: .legacyEnabledTools)
            legacyVoice = try container.decodeIfPresent(String.self, forKey: .legacyVoice)
            legacyThinkingLevel = try container.decodeIfPresent(String.self, forKey: .legacyThinkingLevel)
        }

        enum CodingKeys: String, CodingKey {
            case isMicrophoneEnabled
            case showTranscriptOverlay
            case systemPromptPresets
            case selectedSystemPromptID
            case legacyEnabledTools = "enabledTools"
            case legacyVoice = "selectedVoice"
            case legacyThinkingLevel = "thinkingLevel"
        }
    }
}

private final class GeminiLiveDevelopmentFileStore {
    private let fileURL: URL

    init(fileURL: URL = GeminiLiveDevelopmentFileStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        let trimmedKey = payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.isEmpty ? nil : trimmedKey
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        let payload = Payload(apiKey: value)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct Payload: Codable {
        let apiKey: String
    }

    private static var defaultFileURL: URL {
        let fileManager = FileManager.default
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        return supportDirectory
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("Development", isDirectory: true)
            .appendingPathComponent("gemini-api-key.json")
    }
}

private final class GeminiLiveKeychainStore {
    private let service = "dev.notch"
    private let account = "GeminiLiveAPIKey"

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        delete()

        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
