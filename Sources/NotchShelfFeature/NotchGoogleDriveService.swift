import Foundation
import Security
import UniformTypeIdentifiers

public enum GoogleDriveError: LocalizedError {
    case notConnected
    case cannotResolveBookmark
    case invalidQuery
    case folderCheckFailed
    case folderCreationFailed
    case uploadFailed
    case makePublicFailed
    case makePrivateFailed
    case deleteFailed
    case refreshFailed(String)
    case fileTooLarge
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Chưa kết nối Google Drive."
        case .cannotResolveBookmark:
            return "Không thể truy cập tệp tin (hết hạn bookmark)."
        case .invalidQuery:
            return "Lỗi chuẩn bị truy vấn Google Drive."
        case .folderCheckFailed:
            return "Không thể kiểm tra thư mục lưu trữ trên Google Drive."
        case .folderCreationFailed:
            return "Không thể tạo thư mục lưu trữ trên Google Drive."
        case .uploadFailed:
            return "Tải lên Google Drive thất bại."
        case .makePublicFailed:
            return "Không thể bật chế độ chia sẻ công khai."
        case .makePrivateFailed:
            return "Không thể tắt chế độ chia sẻ công khai."
        case .deleteFailed:
            return "Không thể xóa file trên Google Drive."
        case .refreshFailed(let reason):
            return "Lỗi gia hạn kết nối: \(reason)"
        case .fileTooLarge:
            return "Kích thước file vượt quá giới hạn 100MB."
        case .fileNotFound:
            return "Không tìm thấy file trên Google Drive."
        }
    }
}

public protocol NotchShelfDriveDeleting: Sendable {
    func deleteFile(fileId: String, portalBaseURL: URL) async throws
}

private struct KeychainHelper {
    static var service: String {
        ProcessInfo.processInfo.environment["NOTCH_GDRIVE_KEYCHAIN_SERVICE"] ?? "dev.notch.gdrive"
    }

    static func save(key: String, value: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
        ]
        let updateStatus = SecItemUpdate(baseQuery(key: key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var query = baseQuery(key: key)
        query[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return nil
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

private enum GoogleDriveCredentialStorage {
    private enum Mode {
        case developmentFile
        case keychain
    }

    private static var mode: Mode {
        if let override = ProcessInfo.processInfo.environment["NOTCH_DEV_GDRIVE_FILE_STORAGE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override == "0" ? .keychain : .developmentFile
        }

#if DEBUG
        return .developmentFile
#else
        return .keychain
#endif
    }

    static func save(key: String, value: String) -> Bool {
        switch mode {
        case .developmentFile:
            return GoogleDriveDevelopmentFileStore.save(key: key, value: value)
        case .keychain:
            return KeychainHelper.save(key: key, value: value)
        }
    }

    static func read(key: String) -> String? {
        switch mode {
        case .developmentFile:
            return GoogleDriveDevelopmentFileStore.read(key: key)
        case .keychain:
            return KeychainHelper.read(key: key)
        }
    }

    static func delete(key: String) {
        switch mode {
        case .developmentFile:
            GoogleDriveDevelopmentFileStore.delete(key: key)
        case .keychain:
            KeychainHelper.delete(key: key)
        }
    }
}

private enum GoogleDriveDevelopmentFileStore {
    private static let lock = NSLock()

    private static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCH_GDRIVE_DEVELOPMENT_CREDENTIALS_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch", isDirectory: true)
            .appendingPathComponent("Development", isDirectory: true)
            .appendingPathComponent("google-drive-credentials.json", isDirectory: false)
    }

    static func save(key: String, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var values = load()
        values[key] = value
        do {
            let url = fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(values)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return load()[key]
    }

    static func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }

        var values = load()
        values.removeValue(forKey: key)
        let url = fileURL
        guard !values.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }
}

private actor GoogleDriveNewUploadGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }
        waiters.removeFirst().resume()
    }
}

public final class NotchGoogleDriveService: Sendable {
    public static let shared = NotchGoogleDriveService()
    public static let maximumUploadByteCount = 100 * 1024 * 1024
    private static let newUploadGate = GoogleDriveNewUploadGate()

    public init() {}

    public var isConnected: Bool {
        guard accessToken != nil else {
            return false
        }
        if let expiry = expiresAtDate, expiry > Date().addingTimeInterval(60) {
            return true
        }
        return refreshToken != nil
    }

    public var accessToken: String? {
        get { GoogleDriveCredentialStorage.read(key: "AccessToken") }
        set {
            if let newValue {
                _ = GoogleDriveCredentialStorage.save(key: "AccessToken", value: newValue)
            } else {
                GoogleDriveCredentialStorage.delete(key: "AccessToken")
            }
        }
    }

    public var refreshToken: String? {
        get { GoogleDriveCredentialStorage.read(key: "RefreshToken") }
        set {
            if let newValue {
                _ = GoogleDriveCredentialStorage.save(key: "RefreshToken", value: newValue)
            } else {
                GoogleDriveCredentialStorage.delete(key: "RefreshToken")
            }
        }
    }

    public var expiresAtDate: Date? {
        get {
            guard let raw = GoogleDriveCredentialStorage.read(key: "ExpiresAt") else { return nil }
            let interval = Double(raw) ?? 0
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let newValue {
                let raw = String(newValue.timeIntervalSince1970)
                _ = GoogleDriveCredentialStorage.save(key: "ExpiresAt", value: raw)
            } else {
                GoogleDriveCredentialStorage.delete(key: "ExpiresAt")
            }
        }
    }

    public var folderId: String? {
        get { GoogleDriveCredentialStorage.read(key: "FolderId") }
        set {
            if let newValue {
                _ = GoogleDriveCredentialStorage.save(key: "FolderId", value: newValue)
            } else {
                GoogleDriveCredentialStorage.delete(key: "FolderId")
            }
        }
    }

    public func clearCredentials() {
        accessToken = nil
        refreshToken = nil
        expiresAtDate = nil
        folderId = nil
    }

    public func storeCredentials(accessToken: String, refreshToken: String?, expiresAtDate: Date) -> Bool {
        guard GoogleDriveCredentialStorage.save(key: "AccessToken", value: accessToken),
              GoogleDriveCredentialStorage.save(key: "ExpiresAt", value: String(expiresAtDate.timeIntervalSince1970)) else {
            return false
        }

        if let refreshToken {
            guard GoogleDriveCredentialStorage.save(key: "RefreshToken", value: refreshToken) else {
                return false
            }
        } else {
            GoogleDriveCredentialStorage.delete(key: "RefreshToken")
        }
        GoogleDriveCredentialStorage.delete(key: "FolderId")
        return true
    }

    public func exchangeHandoffToken(
        _ handoffToken: String,
        codeVerifier: String,
        portalBaseURL: URL
    ) async throws -> (accessToken: String, refreshToken: String?, expiresIn: Int?) {
        let exchangeURL = normalizedPortalBaseURL(portalBaseURL).appendingPathComponent("api/auth/google-drive/exchange")
        var request = URLRequest(url: exchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "handoff_token": handoffToken,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let reason = Self.errorMessage(from: data) ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw GoogleDriveError.refreshFailed(reason)
        }

        struct ExchangeResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
        }

        let payload = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        return (payload.access_token, payload.refresh_token, payload.expires_in)
    }

    public func ensureValidAccessToken(portalBaseURL: URL) async throws -> String {
        guard let token = accessToken else {
            clearCredentials()
            throw GoogleDriveError.notConnected
        }

        if let exp = expiresAtDate, exp > Date().addingTimeInterval(60) {
            return token
        }

        guard let refresh = refreshToken else {
            clearCredentials()
            throw GoogleDriveError.notConnected
        }

        let refreshURL = normalizedPortalBaseURL(portalBaseURL).appendingPathComponent("api/auth/google-drive/refresh")

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["refresh_token": refresh]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            clearCredentials()
            throw GoogleDriveError.notConnected
        }
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = Self.errorMessage(from: data) ?? "HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0)"
            throw GoogleDriveError.refreshFailed(errorMsg)
        }

        struct RefreshResponse: Decodable {
            let access_token: String
            let expires_in: Int
            let refresh_token: String?
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(RefreshResponse.self, from: data)

        guard KeychainHelper.save(key: "AccessToken", value: payload.access_token),
              KeychainHelper.save(
                  key: "ExpiresAt",
                  value: String(Date().addingTimeInterval(Double(payload.expires_in)).timeIntervalSince1970)
              ) else {
            throw GoogleDriveError.refreshFailed("Không thể lưu thông tin xác thực an toàn.")
        }
        if let newRefresh = payload.refresh_token,
           !KeychainHelper.save(key: "RefreshToken", value: newRefresh) {
            throw GoogleDriveError.refreshFailed("Không thể lưu thông tin xác thực an toàn.")
        }

        return payload.access_token
    }

    private func normalizedPortalBaseURL(_ portalBaseURL: URL) -> URL {
        let env = ProcessInfo.processInfo.environment
        let origin = env["NOTCH_WEB_ORIGIN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedAPI = origin.isEmpty ? portalBaseURL : (URL(string: origin) ?? portalBaseURL)

        var resolvedAPIString = resolvedAPI.absoluteString
        if resolvedAPIString.hasSuffix("/api") {
            resolvedAPIString = String(resolvedAPIString.dropLast(4))
        } else if resolvedAPIString.hasSuffix("/api/") {
            resolvedAPIString = String(resolvedAPIString.dropLast(5))
        }
        return URL(string: resolvedAPIString) ?? resolvedAPI
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["error"] as? String
    }

    private func rejectInvalidAuthorization(_ response: HTTPURLResponse) throws {
        guard response.statusCode == 401 else {
            return
        }
        clearCredentials()
        throw GoogleDriveError.notConnected
    }

    private func getOrCreateFolderId(accessToken: String) async throws -> String {
        if let existing = self.folderId {
            return existing
        }

        let query = "mimeType = 'application/vnd.google-apps.folder' and name = 'Notch Shelf' and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw GoogleDriveError.invalidQuery
        }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.folderCheckFailed
        }
        try rejectInvalidAuthorization(httpResponse)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GoogleDriveError.folderCheckFailed
        }

        struct FilesResponse: Decodable {
            struct FileItem: Decodable {
                let id: String
                let name: String
            }
            let files: [FileItem]
        }

        let decoder = JSONDecoder()
        if let filesRes = try? decoder.decode(FilesResponse.self, from: data),
           let firstFolder = filesRes.files.first {
            self.folderId = firstFolder.id
            return firstFolder.id
        }

        // Create folder
        var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": "Notch Shelf",
            "mimeType": "application/vnd.google-apps.folder"
        ]
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let httpCreateResponse = createResponse as? HTTPURLResponse else {
            throw GoogleDriveError.folderCreationFailed
        }
        try rejectInvalidAuthorization(httpCreateResponse)
        guard (200...299).contains(httpCreateResponse.statusCode) else {
            throw GoogleDriveError.folderCreationFailed
        }

        struct FolderCreateResponse: Decodable {
            let id: String
        }

        let folder = try decoder.decode(FolderCreateResponse.self, from: createData)
        self.folderId = folder.id
        return folder.id
    }

    public func upload(
        name: String,
        mimeType: String,
        data: Data,
        portalBaseURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try await Self.newUploadGate.run { [self] in
            try await performUpload(
                name: name,
                mimeType: mimeType,
                data: data,
                portalBaseURL: portalBaseURL,
                onProgress: onProgress
            )
        }
    }

    private func performUpload(
        name: String,
        mimeType: String,
        data: Data,
        portalBaseURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        try Task.checkCancellation()
        guard data.count <= Self.maximumUploadByteCount else {
            throw GoogleDriveError.fileTooLarge
        }
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)
        let parentFolderId = try await getOrCreateFolderId(accessToken: token)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)

        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentFolderId]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)

        // Media part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // End part
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let progressDelegate = onProgress.map { UploadProgressDelegate(onProgress: $0) }
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: request, delegate: progressDelegate)
        guard let httpUploadResponse = uploadResponse as? HTTPURLResponse else {
            throw GoogleDriveError.uploadFailed
        }
        try rejectInvalidAuthorization(httpUploadResponse)
        guard (200...299).contains(httpUploadResponse.statusCode) else {
            if let errorMsg = String(data: uploadData, encoding: .utf8) {
                print("Google Drive upload error response: \(errorMsg)")
            }
            throw GoogleDriveError.uploadFailed
        }

        struct UploadResponse: Decodable {
            let id: String
        }
        let payload = try JSONDecoder().decode(UploadResponse.self, from: uploadData)
        return payload.id
    }

    public func updateFile(
        fileId: String,
        name: String,
        mimeType: String,
        data: Data,
        portalBaseURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        guard data.count <= Self.maximumUploadByteCount else {
            throw GoogleDriveError.fileTooLarge
        }
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=multipart")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)

        let metadata: [String: Any] = [
            "name": name
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)

        // Media part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // End part
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let progressDelegate = onProgress.map { UploadProgressDelegate(onProgress: $0) }
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: request, delegate: progressDelegate)
        guard let httpResponse = uploadResponse as? HTTPURLResponse else {
            throw GoogleDriveError.uploadFailed
        }
        try rejectInvalidAuthorization(httpResponse)

        if httpResponse.statusCode == 404 {
            throw GoogleDriveError.fileNotFound
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorMsg = String(data: uploadData, encoding: .utf8) {
                print("Google Drive update error response: \(errorMsg)")
            }
            throw GoogleDriveError.uploadFailed
        }

        return fileId
    }

    public func makeFilePublic(fileId: String, portalBaseURL: URL) async throws {
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "role": "reader",
            "type": "anyone"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.makePublicFailed
        }
        try rejectInvalidAuthorization(httpResponse)

        if httpResponse.statusCode == 404 {
            throw GoogleDriveError.fileNotFound
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorMsg = String(data: data, encoding: .utf8) {
                print("Google Drive make public error response: \(errorMsg)")
            }
            throw GoogleDriveError.makePublicFailed
        }
    }

    public func deleteFile(fileId: String, portalBaseURL: URL) async throws {
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.deleteFailed
        }
        try rejectInvalidAuthorization(httpResponse)

        if httpResponse.statusCode == 404 {
            return
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorMsg = String(data: data, encoding: .utf8) {
                print("Google Drive delete error response: \(errorMsg)")
            }
            throw GoogleDriveError.deleteFailed
        }
    }

    public func fileExists(fileId: String, portalBaseURL: URL) async throws -> Bool {
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        try rejectInvalidAuthorization(httpResponse)

        return httpResponse.statusCode == 200
    }

    public func makeFilePrivate(fileId: String, portalBaseURL: URL) async throws {
        let token = try await ensureValidAccessToken(portalBaseURL: portalBaseURL)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions/anyoneWithLink")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.makePrivateFailed
        }
        try rejectInvalidAuthorization(httpResponse)

        if httpResponse.statusCode == 404 {
            let exists = try await fileExists(fileId: fileId, portalBaseURL: portalBaseURL)
            if exists {
                // Permission already deleted / already private, no-op
                return
            } else {
                throw GoogleDriveError.fileNotFound
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorMsg = String(data: data, encoding: .utf8) {
                print("Google Drive make private error response: \(errorMsg)")
            }
            throw GoogleDriveError.makePrivateFailed
        }
    }
}

extension NotchGoogleDriveService: NotchShelfDriveDeleting {}

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}
