import Foundation
import Security

final class NotchKeychainSecretsManager: @unchecked Sendable {
    static let shared = NotchKeychainSecretsManager()
    
    private let service = "dev.notch"
    private let account = "app-secrets"
    private let lock = NSLock()
    
    private init() {}
    
    private var testStorage: [String: String] = [:]
    private var cachedDict: [String: String]?
    
    private var isTesting: Bool {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        if ProcessInfo.processInfo.environment.keys.contains(where: { $0.contains("TEST") }) { return true }
        if ProcessInfo.processInfo.processName.lowercased().contains("test") { return true }
        #endif
        return false
    }
    
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
    
    func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        let dict = readAll()
        return dict[key]
    }
    
    func save(key: String, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        var dict = readAll()
        dict[key] = value
        return saveAll(dict)
    }
    
    func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        
        var dict = readAll()
        dict.removeValue(forKey: key)
        _ = saveAll(dict)
    }
    
    private func readAll() -> [String: String] {
        if isTesting {
            return testStorage
        }
        
        if let cached = cachedDict {
            return cached
        }
        
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            cachedDict = [:]
            return [:]
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            cachedDict = [:]
            return [:]
        }
        cachedDict = dict
        return dict
    }
    
    private func saveAll(_ dict: [String: String]) -> Bool {
        if isTesting {
            testStorage = dict
            return true
        }
        
        SecItemDelete(baseQuery as CFDictionary)
        
        guard !dict.isEmpty else {
            cachedDict = dict
            return true
        }
        
        guard let data = try? JSONEncoder().encode(dict) else {
            return false
        }
        
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            cachedDict = dict
            return true
        }
        return false
    }
}
