import Foundation
import SQLite3

final class MailSQLiteManager: @unchecked Sendable {
    static let shared = MailSQLiteManager()
    
    private var db: OpaquePointer?
    private let lock = NSLock()
    
    private func findEnvelopeIndexPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mailPath = home.appendingPathComponent("Library/Mail")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: mailPath, includingPropertiesForKeys: nil)
            let vFolders = contents.filter { $0.lastPathComponent.hasPrefix("V") }.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            
            for folder in vFolders {
                let envelopePath = folder.appendingPathComponent("MailData/Envelope Index").path
                if FileManager.default.fileExists(atPath: envelopePath) {
                    return envelopePath
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    func openDatabase() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if db != nil { return true }
        guard let path = findEnvelopeIndexPath() else { return false }
        
        // Open in read-only mode to avoid locking issues with Mail app
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            return false
        }
        return true
    }
    
    func closeDatabase() {
        lock.lock(); defer { lock.unlock() }
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    func fetchRecentEmails(limit: Int = 10) -> [[String: Any]] {
        guard openDatabase() else { return [] }
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
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
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
        }
        
        sqlite3_finalize(statement)
        return results
    }
    
    func searchEmails(keyword: String, limit: Int = 20) -> [[String: Any]] {
        guard openDatabase() else { return [] }
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
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
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
        }
        
        sqlite3_finalize(statement)
        return results
    }
}
