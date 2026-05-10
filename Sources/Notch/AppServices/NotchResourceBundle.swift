import Foundation

enum NotchResourceBundle {
    private static let bundleName = "Notch_Notch.bundle"

    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        resourceBundle?.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }

    private static var resourceBundle: Bundle? {
        for candidate in bundleCandidates() {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return nil
    }

    private static func bundleCandidates() -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)", isDirectory: true))

        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(executableDirectory.appendingPathComponent(bundleName, isDirectory: true))

        return candidates
    }
}
