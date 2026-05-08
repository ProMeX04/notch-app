import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginController {

    // MARK: - State

    /// Whether the app is currently registered to launch at login.
    /// Uses SMAppService when available, otherwise falls back to a
    /// manually-managed LaunchAgent plist.
    var isEnabled: Bool {
        if smAppServiceAvailable {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: launchAgentPlistPath)
    }

    /// Call before reading `isEnabled` to make sure macOS has the latest status.
    func refreshStatus() {
        if smAppServiceAvailable {
            _ = SMAppService.mainApp.status
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        // Try the modern SMAppService path first.
        if smAppServiceAvailable {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return
        }

        // Fallback: manually manage a LaunchAgent plist.
        if enabled {
            try installLaunchAgent()
        } else {
            try uninstallLaunchAgent()
        }
    }

    // MARK: - SMAppService availability

    /// `SMAppService.mainApp` returns `.notFound` when the app isn't
    /// in /Applications, isn't properly signed, or is running from a
    /// build directory. We treat that as "unavailable" and use the
    /// LaunchAgent fallback instead.
    private var smAppServiceAvailable: Bool {
        let status = SMAppService.mainApp.status
        return status != .notFound
    }

    // MARK: - LaunchAgent fallback

    private var launchAgentDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents"
    }

    private var launchAgentPlistPath: String {
        "\(launchAgentDir)/dev.notch.plist"
    }

    private func installLaunchAgent() throws {
        let appPath = currentAppBundlePath()

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>dev.notch</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)/Contents/MacOS/Notch</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """

        let dir = launchAgentDir
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        try plist.write(toFile: launchAgentPlistPath, atomically: true, encoding: .utf8)
    }

    private func uninstallLaunchAgent() throws {
        let path = launchAgentPlistPath
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    /// Returns the path to the running `.app` bundle (e.g. `/Applications/Notch.app`
    /// or `…/dist/Notch.app`).
    private func currentAppBundlePath() -> String {
        Bundle.main.bundlePath
    }
}
