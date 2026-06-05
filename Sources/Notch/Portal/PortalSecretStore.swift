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

final class PortalSecretStore {
    private let keychainStore: PortalKeychainStore

    init(processInfo: ProcessInfo, developmentFileURL: URL, keychainAccount: String) {
        keychainStore = PortalKeychainStore(account: keychainAccount)
    }

    func read() -> String? {
        keychainStore.read()
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        keychainStore.save(value)
    }

    func delete() {
        keychainStore.delete()
    }
}
