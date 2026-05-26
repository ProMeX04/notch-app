import Foundation

enum ProbeResources {
    private static var resourceBundleURL: URL? {
        if let envPath = ProcessInfo.processInfo.environment["NOTCH_RESOURCES_BUNDLE_PATH"] {
            let candidate = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let mainBundle = Bundle.main.bundleURL
        let bundleName = "Notch_Notch.bundle"

        let candidates = [
            mainBundle.appendingPathComponent(bundleName),
            mainBundle.appendingPathComponent("Contents/Resources/\(bundleName)"),
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        NotchLog.mediaRemote.error("Could not locate \(bundleName)")
        return nil
    }

    static var mediaRemoteAdapterScriptURL: URL? {
        resourceURL(named: "mediaremote-adapter.pl")
    }

    static var mediaRemoteFrameworkURL: URL? {
        resourceURL(named: "MediaRemoteAdapter.framework")
    }

    static var mediaRemoteTestClientURL: URL? {
        resourceURL(named: "MediaRemoteAdapterTestClient")
    }

    private static func resourceURL(named name: String) -> URL? {
        guard let resourceBundleURL else { return nil }
        let url = resourceBundleURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NotchLog.mediaRemote.error("Missing MediaRemote resource: \(name)")
            return nil
        }
        return url
    }
}
