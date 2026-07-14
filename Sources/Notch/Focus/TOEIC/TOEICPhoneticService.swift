import Foundation

/// Offline IPA lookup from bundled app resources (no runtime AI).
/// Sources (first hit wins): card.phonetic → `toeic_phonetics.json` → UserDefaults overrides.
@MainActor
final class TOEICPhoneticService: ObservableObject {
    static let shared = TOEICPhoneticService()

    /// Bundled map: lowercase word → `/ipa/`.
    private let bundled: [String: String]
    /// Optional user overrides (manual edits only — not AI cache).
    @Published private(set) var overrides: [String: String] = [:]
    /// Kept for UI compatibility (always empty — no network IPA).
    @Published private(set) var loadingWords: Set<String> = []

    private let overridesKey = "notch.toeic.ipa.overrides.v1"

    private init() {
        bundled = Self.loadBundledIPA()
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = decoded
        }
    }

    func phonetic(for card: TOEICVocabCard) -> String {
        if let fromCard = cleanedIPA(card.phonetic), !fromCard.isEmpty {
            return fromCard
        }
        let key = normalize(card.word)
        if let o = overrides[key], let cleaned = cleanedIPA(o), !cleaned.isEmpty {
            return cleaned
        }
        if let b = bundled[key], let cleaned = cleanedIPA(b), !cleaned.isEmpty {
            return cleaned
        }
        return ""
    }

    /// Sync only — IPA is pre-baked into resources (no API).
    func ensurePhonetic(for card: TOEICVocabCard) async -> String {
        phonetic(for: card)
    }

    private static func loadBundledIPA() -> [String: String] {
        let url =
            NotchResourceBundle.url(forResource: "toeic_phonetics", withExtension: "json", subdirectory: "TOEIC")
            ?? NotchResourceBundle.url(forResource: "toeic_phonetics", withExtension: "json")
            ?? Bundle.main.url(forResource: "toeic_phonetics", withExtension: "json", subdirectory: "TOEIC")
            ?? Bundle.main.url(forResource: "toeic_phonetics", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        var out: [String: String] = [:]
        out.reserveCapacity(raw.count)
        for (k, v) in raw {
            let key = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, let ipa = cleanedIPAStatic(v), !ipa.isEmpty else { continue }
            out[key] = ipa
        }
        return out
    }

    private func cleanedIPA(_ raw: String) -> String? {
        Self.cleanedIPAStatic(raw)
    }

    private static func cleanedIPAStatic(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = s.firstIndex(of: "/"),
           let end = s[s.index(after: start)...].firstIndex(of: "/") {
            s = String(s[start...end])
        }
        if s.count >= 3, s.hasPrefix("/"), s.hasSuffix("/") {
            return s
        }
        let bare = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard bare.count >= 1 else { return nil }
        if bare.range(of: #"^[A-Za-z'\\-]+$"#, options: .regularExpression) != nil {
            return nil
        }
        return "/\(bare)/"
    }

    private func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
