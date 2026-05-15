import AppKit

@MainActor
protocol MediaWorkspaceProtocol: AnyObject {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    func icon(forFile path: String) -> NSImage
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration)
}

@MainActor
final class MediaWorkspace: MediaWorkspaceProtocol {
    static let shared = MediaWorkspace()

    private init() {}

    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func icon(forFile path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) {
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
