import Foundation
import SQLite3
import NotchMailParserCore

enum MailSQLiteError: LocalizedError {
    case envelopeIndexNotFound
    case databaseOpenFailed(path: String, code: Int32, message: String)
    case statementPrepareFailed(operation: String, code: Int32, message: String)
    case invalidMessageId(String)
    case messageNotFound(Int64)

    var errorDescription: String? {
        switch self {
        case .envelopeIndexNotFound:
            return "Cannot find Apple Mail database. Please grant Full Disk Access to Notch in System Settings > Privacy & Security."
        case let .databaseOpenFailed(path, code, message):
            return "Cannot open Apple Mail database at \(path) (SQLite \(code): \(message))."
        case let .statementPrepareFailed(operation, code, message):
            return "Cannot query Apple Mail database for \(operation) (SQLite \(code): \(message))."
        case let .invalidMessageId(messageId):
            return "Invalid messageId '\(messageId)'. Use the numeric ID returned by search or list_recent."
        case let .messageNotFound(messageId):
            return "Email not found for messageId \(messageId)."
        }
    }
}

final class MailSQLiteManager: @unchecked Sendable {
    static let shared = MailSQLiteManager()

    private var db: OpaquePointer?
    private var emlxPathCache: [Int64: URL] = [:]
    private let lock = NSLock()

    private func findMailRoot() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mailPath = home.appendingPathComponent("Library/Mail")

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: mailPath, includingPropertiesForKeys: nil)
            let vFolders = contents.filter { $0.lastPathComponent.hasPrefix("V") }.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }

            for folder in vFolders {
                let envelopePath = folder.appendingPathComponent("MailData/Envelope Index").path
                if FileManager.default.fileExists(atPath: envelopePath) {
                    return folder
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func findEnvelopeIndexPath() -> String? {
        findMailRoot()?.appendingPathComponent("MailData/Envelope Index").path
    }
    
    func openDatabase() throws {
        lock.lock(); defer { lock.unlock() }
        if db != nil { return }
        guard let path = findEnvelopeIndexPath() else { throw MailSQLiteError.envelopeIndexNotFound }

        var openedDb: OpaquePointer?
        let result = sqlite3_open_v2(path, &openedDb, SQLITE_OPEN_READONLY, nil)
        if result != SQLITE_OK {
            let message = openedDb.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            if openedDb != nil {
                sqlite3_close(openedDb)
            }
            db = nil
            throw MailSQLiteError.databaseOpenFailed(path: path, code: result, message: message)
        }
        db = openedDb
    }
    
    func closeDatabase() {
        lock.lock(); defer { lock.unlock() }
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    func fetchRecentEmails(limit: Int = 10) throws -> [[String: Any]] {
        try openDatabase()
        lock.lock(); defer { lock.unlock() }
        
        let query = """
        SELECT 
            m.ROWID, 
            s.subject, 
            a.address as sender_email, 
            a.comment as sender_name, 
            m.date_sent, 
            m.summary
        FROM messages m
        JOIN subjects s ON m.subject = s.ROWID
        JOIN addresses a ON m.sender = a.ROWID
        ORDER BY m.date_sent DESC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var results: [[String: Any]] = []
        
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            throw MailSQLiteError.statementPrepareFailed(operation: "recent emails", code: prepareResult, message: message)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let subject = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)) : "(No Subject)"
            let senderEmail = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : ""
            let senderName = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : ""
            let dateSent = sqlite3_column_int64(statement, 4)
            let summary = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : ""

            results.append([
                "id": rowID,
                "subject": subject,
                "sender": senderName.isEmpty ? senderEmail : "\(senderName) <\(senderEmail)>",
                "date": Date(timeIntervalSince1970: TimeInterval(dateSent)).description,
                "summary": summary
            ])
        }

        return results
    }
    
    func fetchEmailById(messageId: String) throws -> [String: Any] {
        guard let rowID = Int64(messageId) else {
            throw MailSQLiteError.invalidMessageId(messageId)
        }

        try openDatabase()
        lock.lock(); defer { lock.unlock() }

        let query = """
        SELECT
            m.ROWID,
            s.subject,
            a.address as sender_email,
            a.comment as sender_name,
            m.date_sent,
            su.summary,
            mb.url
        FROM messages m
        JOIN subjects s ON m.subject = s.ROWID
        JOIN addresses a ON m.sender = a.ROWID
        LEFT JOIN summaries su ON m.summary = su.ROWID
        LEFT JOIN mailboxes mb ON m.mailbox = mb.ROWID
        WHERE m.ROWID = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            throw MailSQLiteError.statementPrepareFailed(operation: "email lookup", code: prepareResult, message: message)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, rowID)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MailSQLiteError.messageNotFound(rowID)
        }

        let subject = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)) : "(No Subject)"
        let senderEmail = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : ""
        let senderName = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : ""
        let dateSent = sqlite3_column_int64(statement, 4)
        let summary = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : ""
        let mailboxURL = sqlite3_column_text(statement, 6) != nil ? String(cString: sqlite3_column_text(statement, 6)) : nil
        let body = resolveEMLXURL(for: rowID, mailboxURL: mailboxURL).flatMap { readBody(fromEMLXAt: $0) }

        return [
            "id": rowID,
            "subject": subject,
            "sender": senderName.isEmpty ? senderEmail : "\(senderName) <\(senderEmail)>",
            "date": Date(timeIntervalSince1970: TimeInterval(dateSent)).description,
            "content": body ?? summary,
            "contentType": body == nil ? "summary" : "body",
            "bodyAvailable": body != nil
        ]
    }

    private func resolveEMLXURL(for rowID: Int64, mailboxURL: String?) -> URL? {
        if let cached = emlxPathCache[rowID], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let mailRoot = findMailRoot() else { return nil }
        let targetName = "\(rowID).emlx"
        let mailboxHint = mailboxURL.flatMap { URL(string: $0)?.lastPathComponent.lowercased() }
        let enumerator = FileManager.default.enumerator(
            at: mailRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var matches: [(score: Int, url: URL)] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == targetName, url.path.contains("/Messages/") else { continue }
            var score = 0
            if let mailboxHint, url.path.lowercased().contains(mailboxHint) { score += 10 }
            matches.append((score, url))
        }

        let resolved = matches.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.url.path < $1.url.path
        }.first?.url
        if let resolved {
            emlxPathCache[rowID] = resolved
        }
        return resolved
    }

    private func readBody(fromEMLXAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return AppleMailBodyParser.parseEMLX(data)
    }

    func searchEmails(keyword: String, limit: Int = 20) throws -> [[String: Any]] {
        try openDatabase()
        lock.lock(); defer { lock.unlock() }
        
        let query = """
        SELECT 
            m.ROWID, 
            s.subject, 
            a.address as sender_email, 
            a.comment as sender_name, 
            m.date_sent, 
            m.summary
        FROM messages m
        JOIN subjects s ON m.subject = s.ROWID
        JOIN addresses a ON m.sender = a.ROWID
        WHERE s.subject LIKE ? OR a.address LIKE ? OR a.comment LIKE ? OR m.summary LIKE ?
        ORDER BY m.date_sent DESC
        LIMIT ?;
        """
        
        var statement: OpaquePointer?
        var results: [[String: Any]] = []
        
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            throw MailSQLiteError.statementPrepareFailed(operation: "email search", code: prepareResult, message: message)
        }
        defer { sqlite3_finalize(statement) }

        let searchPattern = "%\(keyword)%"
        sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (searchPattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            let subject = sqlite3_column_text(statement, 1) != nil ? String(cString: sqlite3_column_text(statement, 1)) : "(No Subject)"
            let senderEmail = sqlite3_column_text(statement, 2) != nil ? String(cString: sqlite3_column_text(statement, 2)) : ""
            let senderName = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : ""
            let dateSent = sqlite3_column_int64(statement, 4)
            let summary = sqlite3_column_text(statement, 5) != nil ? String(cString: sqlite3_column_text(statement, 5)) : ""

            results.append([
                "id": rowID,
                "subject": subject,
                "sender": senderName.isEmpty ? senderEmail : "\(senderName) <\(senderEmail)>",
                "date": Date(timeIntervalSince1970: TimeInterval(dateSent)).description,
                "summary": summary
            ])
        }

        return results
    }
}
