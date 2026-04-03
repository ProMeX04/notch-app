import Foundation

enum ProbeResources {
    private static var resourceBundleURL: URL {
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

        fatalError("Could not locate \(bundleName)")
    }

    static var mediaRemoteAdapterScriptURL: URL {
        resourceBundleURL.appendingPathComponent("mediaremote-adapter.pl")
    }

    static var mediaRemoteFrameworkURL: URL {
        resourceBundleURL.appendingPathComponent("MediaRemoteAdapter.framework")
    }

    static var mediaRemoteTestClientURL: URL {
        resourceBundleURL.appendingPathComponent("MediaRemoteAdapterTestClient")
    }
}
