import AppKit
import Foundation
import NotchGeminiLiveCore
import Security

enum GeminiLiveInputMode: String, Codable, CaseIterable, Identifiable {
    case openMic
    case pushToTalk

    var id: String { rawValue }
}

enum GeminiLiveConnectionMethod: String, Codable, CaseIterable, Identifiable {
    case userAPIKey = "user-api-key"
    case managedServer = "managed-server"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userAPIKey:
            return "API Key"
        case .managedServer:
            return "Notch Account"
        }
    }

    var shortTitle: String {
        switch self {
        case .userAPIKey:
            return "API Key"
        case .managedServer:
            return "Account"
        }
    }

    var setupTitle: String {
        switch self {
        case .userAPIKey:
            return "Enter your Gemini API key."
        case .managedServer:
            return "Sign in to your Notch account."
        }
    }

    var setupDescription: String {
        switch self {
        case .userAPIKey:
            return "Use your own Gemini API key to connect directly."
        case .managedServer:
            return "Sign in securely in your browser. Notch completes OAuth 2.0 with PKCE automatically."
        }
    }

    var manageButtonTitle: String {
        switch self {
        case .userAPIKey:
            return "Open Settings tab"
        case .managedServer:
            return "Open Settings tab"
        }
    }
}

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

enum GeminiLiveChatInputDisplayMode: String, Codable, Equatable {
    case autoCollapse
    case alwaysVisible
    case hidden
}

struct GeminiLiveSettings {
    let isMicrophoneEnabled: Bool
    let inputMode: GeminiLiveInputMode
    let showTranscriptOverlay: Bool
    /// When false, the notch transcript overlay stays visible after the model stops (until disconnect or subs off).
    let transcriptOverlayAutoHide: Bool
    let showLiveChatInput: Bool
    let liveChatInputDisplayMode: GeminiLiveChatInputDisplayMode
    let outputVolume: Double
    let connectionMethod: GeminiLiveConnectionMethod
    let systemPromptPresets: [GeminiSystemPromptPreset]
    let selectedSystemPromptID: String
    let availableLiveModels: [GeminiLiveModel]
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
            inputMode: payload.inputMode ?? .openMic,
            showTranscriptOverlay: payload.showTranscriptOverlay,
            transcriptOverlayAutoHide: payload.transcriptOverlayAutoHide ?? true,
            showLiveChatInput: payload.showLiveChatInput ?? (payload.liveChatInputDisplayMode != .hidden),
            liveChatInputDisplayMode: payload.liveChatInputDisplayMode ?? ((payload.showLiveChatInput ?? true) ? .autoCollapse : .hidden),
            outputVolume: payload.outputVolume ?? 1,
            connectionMethod: payload.connectionMethod ?? .userAPIKey,
            systemPromptPresets: payload.systemPromptPresets ?? GeminiSystemPromptPreset.defaultPresets,
            selectedSystemPromptID: payload.selectedSystemPromptID ?? GeminiSystemPromptPreset.defaultPreset.id,
            availableLiveModels: payload.availableLiveModels ?? []
        )
    }

    func save(_ settings: GeminiLiveSettings) {
        let payload = Payload(
            isMicrophoneEnabled: settings.isMicrophoneEnabled,
            inputMode: settings.inputMode,
            showTranscriptOverlay: settings.showTranscriptOverlay,
            transcriptOverlayAutoHide: settings.transcriptOverlayAutoHide,
            showLiveChatInput: settings.showLiveChatInput,
            liveChatInputDisplayMode: settings.liveChatInputDisplayMode,
            outputVolume: settings.outputVolume,
            connectionMethod: settings.connectionMethod,
            systemPromptPresets: settings.systemPromptPresets,
            selectedSystemPromptID: settings.selectedSystemPromptID,
            availableLiveModels: settings.availableLiveModels
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private struct Payload: Codable {
        let isMicrophoneEnabled: Bool
        let inputMode: GeminiLiveInputMode?
        let showTranscriptOverlay: Bool
        let transcriptOverlayAutoHide: Bool?
        let showLiveChatInput: Bool?
        let liveChatInputDisplayMode: GeminiLiveChatInputDisplayMode?
        let outputVolume: Double?
        let connectionMethod: GeminiLiveConnectionMethod?
        let systemPromptPresets: [GeminiSystemPromptPreset]?
        let selectedSystemPromptID: String?
        let availableLiveModels: [GeminiLiveModel]?
        init(
            isMicrophoneEnabled: Bool,
            inputMode: GeminiLiveInputMode,
            showTranscriptOverlay: Bool,
            transcriptOverlayAutoHide: Bool,
            showLiveChatInput: Bool,
            liveChatInputDisplayMode: GeminiLiveChatInputDisplayMode,
            outputVolume: Double,
            connectionMethod: GeminiLiveConnectionMethod,
            systemPromptPresets: [GeminiSystemPromptPreset],
            selectedSystemPromptID: String,
            availableLiveModels: [GeminiLiveModel]
        ) {
            self.isMicrophoneEnabled = isMicrophoneEnabled
            self.inputMode = inputMode
            self.showTranscriptOverlay = showTranscriptOverlay
            self.transcriptOverlayAutoHide = transcriptOverlayAutoHide
            self.showLiveChatInput = showLiveChatInput
            self.liveChatInputDisplayMode = liveChatInputDisplayMode
            self.outputVolume = outputVolume
            self.connectionMethod = connectionMethod
            self.systemPromptPresets = systemPromptPresets
            self.selectedSystemPromptID = selectedSystemPromptID
            self.availableLiveModels = availableLiveModels
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isMicrophoneEnabled, forKey: .isMicrophoneEnabled)
            try container.encodeIfPresent(inputMode, forKey: .inputMode)
            try container.encode(showTranscriptOverlay, forKey: .showTranscriptOverlay)
            try container.encode(transcriptOverlayAutoHide ?? true, forKey: .transcriptOverlayAutoHide)
            try container.encode(showLiveChatInput ?? true, forKey: .showLiveChatInput)
            try container.encodeIfPresent(liveChatInputDisplayMode, forKey: .liveChatInputDisplayMode)
            try container.encodeIfPresent(outputVolume, forKey: .outputVolume)
            try container.encodeIfPresent(connectionMethod, forKey: .connectionMethod)
            try container.encodeIfPresent(systemPromptPresets, forKey: .systemPromptPresets)
            try container.encodeIfPresent(selectedSystemPromptID, forKey: .selectedSystemPromptID)
            try container.encodeIfPresent(availableLiveModels, forKey: .availableLiveModels)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isMicrophoneEnabled = try container.decode(Bool.self, forKey: .isMicrophoneEnabled)
            inputMode = try container.decodeIfPresent(GeminiLiveInputMode.self, forKey: .inputMode)
            showTranscriptOverlay = try container.decode(Bool.self, forKey: .showTranscriptOverlay)
            transcriptOverlayAutoHide = try container.decodeIfPresent(Bool.self, forKey: .transcriptOverlayAutoHide)
            showLiveChatInput = try container.decodeIfPresent(Bool.self, forKey: .showLiveChatInput)
            liveChatInputDisplayMode = try container.decodeIfPresent(GeminiLiveChatInputDisplayMode.self, forKey: .liveChatInputDisplayMode)
            outputVolume = try container.decodeIfPresent(Double.self, forKey: .outputVolume)
            connectionMethod = try container.decodeIfPresent(GeminiLiveConnectionMethod.self, forKey: .connectionMethod)
            systemPromptPresets = try container.decodeIfPresent([GeminiSystemPromptPreset].self, forKey: .systemPromptPresets)
            selectedSystemPromptID = try container.decodeIfPresent(String.self, forKey: .selectedSystemPromptID)
            availableLiveModels = try container.decodeIfPresent([GeminiLiveModel].self, forKey: .availableLiveModels)
        }

        enum CodingKeys: String, CodingKey {
            case isMicrophoneEnabled
            case inputMode
            case showTranscriptOverlay
            case transcriptOverlayAutoHide
            case showLiveChatInput
            case liveChatInputDisplayMode
            case outputVolume
            case connectionMethod
            case systemPromptPresets
            case selectedSystemPromptID
            case availableLiveModels
        }
    }
}

enum GeminiAgentAvatarStoreError: LocalizedError {
    case unreadableImage
    case failedToPersist

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The selected file couldn't be used as an avatar image."
        case .failedToPersist:
            return "The avatar image couldn't be saved."
        }
    }
}

final class GeminiAgentAvatarStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let avatarsDirectory: URL

    init(
        fileManager: FileManager = .default,
        avatarsDirectory: URL = GeminiLiveStoragePaths.agentAvatarsDirectory
    ) {
        GeminiLiveStoragePaths.prepare(fileManager: fileManager)
        self.fileManager = fileManager
        self.avatarsDirectory = avatarsDirectory
    }

    func saveImage(from sourceURL: URL, presetID: String) throws -> String {
        guard NSImage(contentsOf: sourceURL) != nil else {
            throw GeminiAgentAvatarStoreError.unreadableImage
        }

        guard let imageData = try? Data(contentsOf: sourceURL), !imageData.isEmpty else {
            throw GeminiAgentAvatarStoreError.unreadableImage
        }

        let sanitizedExtension = normalizedImageExtension(for: sourceURL.pathExtension)
        let filename = "\(presetID).\(sanitizedExtension)"
        let destinationURL = avatarsDirectory.appendingPathComponent(filename)

        do {
            try fileManager.createDirectory(at: avatarsDirectory, withIntermediateDirectories: true)
            deleteImage(forPresetID: presetID)
            try imageData.write(to: destinationURL, options: .atomic)
            return filename
        } catch {
            throw GeminiAgentAvatarStoreError.failedToPersist
        }
    }

    func imageURL(for filename: String?) -> URL? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = avatarsDirectory.appendingPathComponent(trimmed)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func deleteImage(named filename: String?) {
        guard let url = imageURL(for: filename) else { return }
        try? fileManager.removeItem(at: url)
    }

    func deleteImage(forPresetID presetID: String) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: avatarsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls where url.deletingPathExtension().lastPathComponent == presetID {
            try? fileManager.removeItem(at: url)
        }
    }

    private func normalizedImageExtension(for pathExtension: String) -> String {
        let trimmed = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "tiff" : trimmed
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
    private let account: String

    init(service: String = "dev.notch", account: String = "GeminiLiveAPIKey") {
        self.account = account
    }

    func read() -> String? {
        NotchKeychainSecretsManager.shared.read(key: account)
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        NotchKeychainSecretsManager.shared.save(key: account, value: value)
    }

    func delete() {
        NotchKeychainSecretsManager.shared.delete(key: account)
    }
}
