import Foundation

/// Bundled TOEIC vocabulary shipped inside the Notch app (`Resources/TOEIC/`).
/// Loaded only via `Bundle.module` / `Bundle.main` — never from ~/Documents or Downloads
/// (avoids macOS Documents TCC prompts).
enum TOEICVocabularyBank {
    private struct VocabRow: Codable {
        let id: Int
        let word: String
        let pos: String?
        let pronunciation: String?
        let meaning: String?
        let example: String?
        let example_vn: String?
    }

    private static let skip: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "and", "or", "is", "are", "be",
    ]

    /// Cached cards loaded once from the app bundle.
    private static let cachedCards: [TOEICVocabCard] = loadFromBundle()

    static var allCards: [TOEICVocabCard] { cachedCards }

    static var count: Int { cachedCards.count }

    private static func loadFromBundle() -> [TOEICVocabCard] {
        let url =
            Bundle.module.url(forResource: "toeic_vocabulary", withExtension: "json", subdirectory: "TOEIC")
            ?? Bundle.module.url(forResource: "toeic_vocabulary", withExtension: "json")
            ?? Bundle.main.url(forResource: "toeic_vocabulary", withExtension: "json", subdirectory: "TOEIC")
            ?? Bundle.main.url(forResource: "toeic_vocabulary", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([VocabRow].self, from: data) else {
            return []
        }

        return rows.compactMap { row in
            let w = row.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, w.count > 1 else { return nil }
            if skip.contains(w.lowercased()) { return nil }
            return TOEICVocabCard(
                id: "vocab-\(row.id)",
                word: w,
                phonetic: {
                    let p = row.pronunciation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return p.isEmpty ? "" : (p.hasPrefix("/") ? p : "/\(p)/")
                }(),
                meaningVI: row.meaning ?? "",
                meaningEN: row.pos ?? "",
                example: {
                    let en = row.example?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !en.isEmpty { return en }
                    return row.example_vn ?? ""
                }(),
                part: {
                    let pos = row.pos?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return pos.isEmpty ? "Word" : pos
                }()
            )
        }
    }
}
