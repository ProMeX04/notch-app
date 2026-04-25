import Combine
import Foundation

final class FocusWebsiteBlocklistStore: ObservableObject {
    static let bridgePort: UInt16 = 44991
    static let bridgeBaseURL = "http://127.0.0.1:\(bridgePort)"

    @Published private(set) var blockedHostsText: String
    @Published private(set) var blockedHosts: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHosts = defaults.stringArray(forKey: Self.blockedHostsDefaultsKey) ?? []
        let normalizedHosts = Self.normalizedHosts(from: storedHosts)
        self.blockedHosts = normalizedHosts
        self.blockedHostsText = Self.text(from: normalizedHosts)

        if normalizedHosts != storedHosts {
            persist(hosts: normalizedHosts)
        }
    }

    func addHost(_ rawHost: String) {
        guard let normalized = Self.normalizedHost(from: rawHost),
              !blockedHosts.contains(normalized) else {
            return
        }

        blockedHosts.append(normalized)
        blockedHostsText = Self.text(from: blockedHosts)
        persist(hosts: blockedHosts)
    }

    func removeHost(_ host: String) {
        blockedHosts.removeAll { $0 == host }
        blockedHostsText = Self.text(from: blockedHosts)
        persist(hosts: blockedHosts)
    }

    func setBlockedHostsText(_ text: String) {
        let normalizedHosts = Self.normalizedHosts(from: text)
        let normalizedText = Self.text(from: normalizedHosts)

        guard normalizedHosts != blockedHosts || normalizedText != blockedHostsText else {
            return
        }

        blockedHosts = normalizedHosts
        blockedHostsText = normalizedText
        persist(hosts: normalizedHosts)
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

    private func persist(hosts: [String]) {
        defaults.set(hosts, forKey: Self.blockedHostsDefaultsKey)
    }

    private static let blockedHostsDefaultsKey = "NotchFocusBlockedHosts"
}
