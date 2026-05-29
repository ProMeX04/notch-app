import Foundation
import Security

final class NotchKeychainSecretsManager: @unchecked Sendable {
    static let shared = NotchKeychainSecretsManager()
    
    private let service = "dev.notch"
    private let account = "app-secrets"
    private let lock = NSLock()
    
    private init() {}
    
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
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
    
    private func saveAll(_ dict: [String: String]) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        
        guard !dict.isEmpty else {
            return true
        }
        
        guard let data = try? JSONEncoder().encode(dict) else {
            return false
        }
        
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
