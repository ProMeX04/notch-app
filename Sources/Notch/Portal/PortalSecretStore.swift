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
    private let service: String
    private let account: String

    init(service: String = "dev.notch", account: String) {
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
