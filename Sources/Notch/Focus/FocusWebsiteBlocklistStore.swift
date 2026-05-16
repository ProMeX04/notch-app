import Combine
import Foundation

enum FocusWebsiteAccessMode: String, CaseIterable, Identifiable {
    case allowAllExceptBlocked
    case blockAllExceptAllowed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allowAllExceptBlocked:
            return "Use all except blocked"
        case .blockAllExceptAllowed:
            return "Only use allowed"
        }
    }
}

final class FocusWebsiteBlocklistStore: ObservableObject {
    static let bridgePort: UInt16 = 44991
    static let bridgeBaseURL = "http://127.0.0.1:\(bridgePort)"

    @Published private(set) var blockedHostsText: String
    @Published private(set) var blockedHosts: [String]
    @Published private(set) var allowedHostsText: String
    @Published private(set) var allowedHosts: [String]
    @Published private(set) var autoOpenUrlsText: String
    @Published private(set) var autoOpenUrls: [String]
    @Published var accessMode: FocusWebsiteAccessMode {
        didSet {
            defaults.set(accessMode.rawValue, forKey: Self.accessModeDefaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHosts = defaults.stringArray(forKey: Self.blockedHostsDefaultsKey) ?? []
        let normalizedHosts = Self.normalizedHosts(from: storedHosts)
        self.blockedHosts = normalizedHosts
        self.blockedHostsText = Self.text(from: normalizedHosts)

        let storedAllowed = defaults.stringArray(forKey: Self.allowedHostsDefaultsKey) ?? ["music.youtube.com"]
        let normalizedAllowed = Self.normalizedHosts(from: storedAllowed)
        self.allowedHosts = normalizedAllowed
        self.allowedHostsText = Self.text(from: normalizedAllowed)

        let storedAutoOpen = defaults.stringArray(forKey: Self.autoOpenUrlsDefaultsKey) ?? []
        self.autoOpenUrls = storedAutoOpen
        self.autoOpenUrlsText = storedAutoOpen.joined(separator: "\n")

        let storedAccessMode = defaults.string(forKey: Self.accessModeDefaultsKey)
        self.accessMode = FocusWebsiteAccessMode(rawValue: storedAccessMode ?? "") ?? .allowAllExceptBlocked

        if normalizedHosts != storedHosts {
            persist(hosts: normalizedHosts, key: Self.blockedHostsDefaultsKey)
        }
        if normalizedAllowed != storedAllowed {
            persist(hosts: normalizedAllowed, key: Self.allowedHostsDefaultsKey)
        }
    }

    func addHost(_ rawHost: String) {
        guard let normalized = Self.normalizedHost(from: rawHost),
              !blockedHosts.contains(normalized) else {
            return
        }

        blockedHosts.append(normalized)
        blockedHostsText = Self.text(from: blockedHosts)
        persist(hosts: blockedHosts, key: Self.blockedHostsDefaultsKey)
    }

    func removeHost(_ host: String) {
        blockedHosts.removeAll { $0 == host }
        blockedHostsText = Self.text(from: blockedHosts)
        persist(hosts: blockedHosts, key: Self.blockedHostsDefaultsKey)
    }

    func addAllowedHost(_ rawHost: String) {
        guard let normalized = Self.normalizedHost(from: rawHost),
              !allowedHosts.contains(normalized) else {
            return
        }

        allowedHosts.append(normalized)
        allowedHostsText = Self.text(from: allowedHosts)
        persist(hosts: allowedHosts, key: Self.allowedHostsDefaultsKey)
    }

    func removeAllowedHost(_ host: String) {
        allowedHosts.removeAll { $0 == host }
        allowedHostsText = Self.text(from: allowedHosts)
        persist(hosts: allowedHosts, key: Self.allowedHostsDefaultsKey)
    }

    func setBlockedHostsText(_ text: String) {
        let normalizedHosts = Self.normalizedHosts(from: text)
        let normalizedText = Self.text(from: normalizedHosts)

        guard normalizedHosts != blockedHosts || normalizedText != blockedHostsText else {
            return
        }

        blockedHosts = normalizedHosts
        blockedHostsText = normalizedText
        persist(hosts: normalizedHosts, key: Self.blockedHostsDefaultsKey)
    }

    func setAutoOpenUrlsText(_ text: String) {
        let urls = text
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard urls != autoOpenUrls else { return }

        autoOpenUrls = urls
        autoOpenUrlsText = urls.joined(separator: "\n")
        defaults.set(urls, forKey: Self.autoOpenUrlsDefaultsKey)
    }

    static func normalizedHosts(from text: String) -> [String] {
        normalizedHosts(
            from: text
                .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
                .map(String.init)
        )
    }

    static func normalizedHosts(from entries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for entry in entries {
            guard let host = normalizedHost(from: entry), !seen.contains(host) else {
                continue
            }

            seen.insert(host)
            result.append(host)
        }

        return result
    }

    static func normalizedHost(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleaned = trimmed
            .replacingOccurrences(of: "*.", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let hostCandidate: String?
        if cleaned.contains("://") {
            hostCandidate = URLComponents(string: cleaned)?.host
        } else {
            hostCandidate = URLComponents(string: "https://\(cleaned)")?.host
        }

        guard let hostCandidate else { return nil }

        let normalized = hostCandidate
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !normalized.isEmpty,
              normalized.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines) == nil else {
            return nil
        }

        return normalized
    }

    private static func text(from hosts: [String]) -> String {
        hosts.joined(separator: "\n")
    }

    private func persist(hosts: [String], key: String) {
        defaults.set(hosts, forKey: key)
    }

    private static let blockedHostsDefaultsKey = "NotchFocusBlockedHosts"
    private static let allowedHostsDefaultsKey = "NotchFocusAllowedHosts"
    private static let autoOpenUrlsDefaultsKey = "NotchFocusAutoOpenUrls"
    private static let accessModeDefaultsKey = "NotchFocusWebsiteAccessMode"
}
