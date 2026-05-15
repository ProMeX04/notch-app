import Foundation
import AppKit

protocol SystemPermissionsManaging: Sendable {
    func hasFullDiskAccess() -> Bool
    func openFullDiskAccessSettings()
}

final class SystemPermissionsManager: SystemPermissionsManaging {
    static let shared = SystemPermissionsManager()

    /// Checks if the application has Full Disk Access.
    /// A common way is to try and list a protected directory like ~/Library/Mail.
    func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mailPath = home.appendingPathComponent("Library/Mail").path
        
        // Try to access the directory content. If FDA is missing, this will fail.
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: mailPath)
            return true
        } catch {
            return false
        }
    }
    
    /// Opens the System Settings at the Full Disk Access page.
    func openFullDiskAccessSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
