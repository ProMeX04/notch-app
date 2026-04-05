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

final class GeminiLiveSecretStore {
    private enum StorageMode {
        case developmentFile
        case keychain
    }

    private let mode: StorageMode
    private let keychainStore: GeminiLiveKeychainStore
    private let developmentFileStore: GeminiLiveDevelopmentFileStore

    init(processInfo: ProcessInfo, developmentFileURL: URL, keychainAccount: String) {
        let env = processInfo.environment
        if let override = env["NOTCH_DEV_PLAINTEXT_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            mode = override == "0" ? .keychain : .developmentFile
        } else {
#if DEBUG
            mode = .developmentFile
#else
            mode = .keychain
#endif
        }

        keychainStore = GeminiLiveKeychainStore(account: keychainAccount)
        developmentFileStore = GeminiLiveDevelopmentFileStore(fileURL: developmentFileURL)
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
    let outputVolume: Double
    let systemPromptPresets: [GeminiSystemPromptPreset]
    let selectedSystemPromptID: String
    let enabledSkillNames: [String]
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

        return GeminiLiveSettings(
            isMicrophoneEnabled: payload.isMicrophoneEnabled,
            showTranscriptOverlay: payload.showTranscriptOverlay,
            outputVolume: payload.outputVolume ?? 1,
            systemPromptPresets: payload.systemPromptPresets ?? GeminiSystemPromptPreset.defaultPresets,
            selectedSystemPromptID: payload.selectedSystemPromptID ?? GeminiSystemPromptPreset.defaultPreset.id,
            enabledSkillNames: payload.enabledSkillNames ?? []
        )
    }

    func save(_ settings: GeminiLiveSettings) {
        let payload = Payload(
            isMicrophoneEnabled: settings.isMicrophoneEnabled,
            showTranscriptOverlay: settings.showTranscriptOverlay,
            outputVolume: settings.outputVolume,
            systemPromptPresets: settings.systemPromptPresets,
            selectedSystemPromptID: settings.selectedSystemPromptID,
            enabledSkillNames: settings.enabledSkillNames
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private struct Payload: Codable {
        let isMicrophoneEnabled: Bool
        let showTranscriptOverlay: Bool
        let outputVolume: Double?
        let systemPromptPresets: [GeminiSystemPromptPreset]?
        let selectedSystemPromptID: String?
        let enabledSkillNames: [String]?

        init(
            isMicrophoneEnabled: Bool,
            showTranscriptOverlay: Bool,
            outputVolume: Double,
            systemPromptPresets: [GeminiSystemPromptPreset],
            selectedSystemPromptID: String,
            enabledSkillNames: [String]
        ) {
            self.isMicrophoneEnabled = isMicrophoneEnabled
            self.showTranscriptOverlay = showTranscriptOverlay
            self.outputVolume = outputVolume
            self.systemPromptPresets = systemPromptPresets
            self.selectedSystemPromptID = selectedSystemPromptID
            self.enabledSkillNames = enabledSkillNames
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isMicrophoneEnabled, forKey: .isMicrophoneEnabled)
            try container.encode(showTranscriptOverlay, forKey: .showTranscriptOverlay)
            try container.encodeIfPresent(outputVolume, forKey: .outputVolume)
            try container.encodeIfPresent(systemPromptPresets, forKey: .systemPromptPresets)
            try container.encodeIfPresent(selectedSystemPromptID, forKey: .selectedSystemPromptID)
            try container.encodeIfPresent(enabledSkillNames, forKey: .enabledSkillNames)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isMicrophoneEnabled = try container.decode(Bool.self, forKey: .isMicrophoneEnabled)
            showTranscriptOverlay = try container.decode(Bool.self, forKey: .showTranscriptOverlay)
            outputVolume = try container.decodeIfPresent(Double.self, forKey: .outputVolume)
            systemPromptPresets = try container.decodeIfPresent([GeminiSystemPromptPreset].self, forKey: .systemPromptPresets)
            selectedSystemPromptID = try container.decodeIfPresent(String.self, forKey: .selectedSystemPromptID)
            enabledSkillNames = try container.decodeIfPresent([String].self, forKey: .enabledSkillNames)
        }

        enum CodingKeys: String, CodingKey {
            case isMicrophoneEnabled
            case showTranscriptOverlay
            case outputVolume
            case systemPromptPresets
            case selectedSystemPromptID
            case enabledSkillNames
        }
    }
}

final class GeminiLiveExecApprovalStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let fileURL: URL

    init(
        fileManager: FileManager = .default,
        fileURL: URL = GeminiLiveStoragePaths.execApprovalsFile
    ) {
        GeminiLiveStoragePaths.prepare(fileManager: fileManager)
        self.fileManager = fileManager
        self.fileURL = fileURL
    }

    func isApproved(command: String, workingDirectory: String?) -> Bool {
        let exact = exactApprovalKey(command: command, workingDirectory: workingDirectory)
        let family = execCommandFamily(for: command).map { familyApprovalKey(family: $0, workingDirectory: workingDirectory) }
        return approvedKeys.contains(exact)
            || (family.map { approvedKeys.contains($0) } ?? false)
    }

    func approveExact(command: String, workingDirectory: String?) {
        var updated = approvedKeys
        updated.insert(exactApprovalKey(command: command, workingDirectory: workingDirectory))
        persist(updated)
    }

    func approveFamily(command: String, workingDirectory: String?) {
        guard let family = execCommandFamily(for: command) else { return }
        var updated = approvedKeys
        updated.insert(familyApprovalKey(family: family, workingDirectory: workingDirectory))
        persist(updated)
    }

    private var approvedKeys: Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return Set(payload.approvedKeys)
    }

    private func persist(_ keys: Set<String>) {
        let payload = Payload(approvedKeys: Array(keys).sorted())
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Ignore persistence failures so approval UI still works for the current session.
        }
    }

    private func exactApprovalKey(command: String, workingDirectory: String?) -> String {
        let normalizedCommand = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
        return "exact:\(normalizedWorkingDirectory(workingDirectory))\n\(normalizedCommand)"
    }

    private func familyApprovalKey(family: String, workingDirectory: String?) -> String {
        "family:\(normalizedWorkingDirectory(workingDirectory))\n\(family)"
    }

    private func normalizedWorkingDirectory(_ workingDirectory: String?) -> String {
        (workingDirectory ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Payload: Codable {
        let approvedKeys: [String]
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
        GeminiLiveStoragePaths.prepare()
        return GeminiLiveStoragePaths.developmentAPIKeyFile
    }
}

private final class GeminiLiveKeychainStore {
    private let service: String
    private let account: String

    init(service: String = "dev.notch", account: String = "GeminiLiveAPIKey") {
        self.service = service
        self.account = account
    }

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
