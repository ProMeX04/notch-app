import Foundation
import Security

enum PortalStoragePaths {
    static var stateRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch", isDirectory: true)
    }

    static var developmentDirectory: URL {
        stateRoot.appendingPathComponent("Development", isDirectory: true)
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true)
            .appendingPathComponent("Portal", isDirectory: true)
    }

    static var deviceContextFile: URL {
        applicationSupportDirectory.appendingPathComponent("device-context.json")
    }

    static var developmentGeminiLiveClientTokenFile: URL {
        developmentDirectory.appendingPathComponent("gemini-live-client-token.json")
    }

    static var developmentNotchAccountAccessTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-access-token.json")
    }

    static var developmentNotchAccountRefreshTokenFile: URL {
        developmentDirectory.appendingPathComponent("notch-account-refresh-token.json")
    }
}

final class PortalKeychainStore {
    private let account: String

    init(service: String = "dev.notch", account: String) {
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

final class PortalDevelopmentFileStore {
    private let fileURL: URL

    init(fileURL: URL) {
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
}

final class PortalSecretStore {
    private enum StorageMode {
        case developmentFile
        case keychain
    }

    private let mode: StorageMode
    private let keychainStore: PortalKeychainStore
    private let developmentFileStore: PortalDevelopmentFileStore

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

        keychainStore = PortalKeychainStore(account: keychainAccount)
        developmentFileStore = PortalDevelopmentFileStore(fileURL: developmentFileURL)
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
