import Foundation

struct NotchCapabilityManifest: Decodable {
    struct Entry: Decodable {
        let key: String
        let name: String
        let description: String
        let requirement: NotchFeatureRequirement
    }

    let version: Int
    let capabilities: [Entry]
}

enum NotchCapabilityManifestLoader {
    private static let resourceName = "notch-capabilities"
    private static let resourceExtension = "json"

    static func defaultRequirements() -> [String: NotchFeatureRequirement] {
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Shared"
        ) else {
            return [:]
        }

        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(NotchCapabilityManifest.self, from: data) else {
            return [:]
        }

        return manifest.capabilities.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.requirement
        }
    }
}
