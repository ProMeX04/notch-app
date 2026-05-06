import Foundation

// MARK: - Trie for O(k) prefix lookup

/// Indexes lowercased text; each node tracks the best (highest useCount) entry
/// in its subtree so prefix lookup is O(k) where k = prefix length.
private final class ChatHistoryTrie {
    final class Node {
        var children: [Character: Node] = [:]
        var terminalText: String?
        var terminalUseCount: Int = 0
        var subtreeBestText: String?
        var subtreeBestUseCount: Int = 0
    }

    let root = Node()

    func insert(text: String, useCount: Int) {
        let key = text.lowercased()
        var node = root
        var path: [Node] = [root]

        for ch in key {
            if node.children[ch] == nil {
                node.children[ch] = Node()
            }
            node = node.children[ch]!
            path.append(node)
        }

        node.terminalText = text
        node.terminalUseCount = useCount

        for n in path.reversed() {
            recomputeSubtreeBest(n)
        }
    }

    func remove(text: String) {
        let key = text.lowercased()
        var node = root
        var path: [(parent: Node, char: Character)] = []

        for ch in key {
            guard let child = node.children[ch] else { return }
            path.append((parent: node, char: ch))
            node = child
        }

        guard node.terminalText == text else { return }
        node.terminalText = nil
        node.terminalUseCount = 0

        // Prune empty leaf nodes bottom-up.
        for (parent, ch) in path.reversed() {
            let child = parent.children[ch]!
            if child.children.isEmpty && child.terminalText == nil {
                parent.children.removeValue(forKey: ch)
            }
            recomputeSubtreeBest(parent)
        }
        recomputeSubtreeBest(node)
    }

    func bestMatch(for prefix: String, excluding: String? = nil) -> String? {
        let key = prefix.lowercased()
        var node = root

        for ch in key {
            guard let child = node.children[ch] else { return nil }
            node = child
        }

        if let best = node.subtreeBestText, best != excluding {
            return best
        }

        // Rare: best is the excluded text → DFS for second-best.
        if excluding != nil {
            return dfsFindBest(node: node, excluding: excluding)
        }
        return nil
    }

    func rebuild(from entries: [String: Int]) {
        root.children.removeAll()
        root.terminalText = nil
        root.terminalUseCount = 0
        root.subtreeBestText = nil
        root.subtreeBestUseCount = 0
        for (text, count) in entries {
            insert(text: text, useCount: count)
        }
    }

    // MARK: - Private

    private func recomputeSubtreeBest(_ node: Node) {
        var bestText: String? = node.terminalText
        var bestCount = node.terminalText != nil ? node.terminalUseCount : 0

        for (_, child) in node.children {
            if child.subtreeBestUseCount > bestCount {
                bestText = child.subtreeBestText
                bestCount = child.subtreeBestUseCount
            }
        }

        node.subtreeBestText = bestText
        node.subtreeBestUseCount = bestText != nil ? bestCount : 0
    }

    private func dfsFindBest(node: Node, excluding: String?) -> String? {
        var best: String?
        var bestCount = 0
        dfs(node: node, excluding: excluding, best: &best, bestCount: &bestCount)
        return best
    }

    private func dfs(node: Node, excluding: String?, best: inout String?, bestCount: inout Int) {
        if let t = node.terminalText, t != excluding, node.terminalUseCount > bestCount {
            best = t
            bestCount = node.terminalUseCount
        }
        for (_, child) in node.children {
            if child.subtreeBestUseCount > bestCount || child.subtreeBestText == excluding {
                dfs(node: child, excluding: excluding, best: &best, bestCount: &bestCount)
            }
        }
    }
}

// MARK: - History Store

@MainActor
final class GeminiLiveChatHistoryStore: ObservableObject {
    private let defaultsKey = "dev.notch.gemini-live-chat.history"
    private let maxHistory = 10_000

    struct Entry: Codable, Equatable {
        var text: String
        var useCount: Int
    }

    private var entriesMap: [String: Int] = [:]        // text → useCount
    @Published private(set) var recencyOrder: [String] = []
    private let trie = ChatHistoryTrie()

    var history: [String] { recencyOrder }

    static let shared = GeminiLiveChatHistoryStore()

    private init() { load() }

    // MARK: - Public API

    func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Recency
        recencyOrder.removeAll { $0 == trimmed }
        recencyOrder.insert(trimmed, at: 0)

        // Frequency + trie
        let oldCount = entriesMap[trimmed] ?? 0
        let newCount = oldCount + 1
        entriesMap[trimmed] = newCount

        if oldCount > 0 { trie.remove(text: trimmed) }
        trie.insert(text: trimmed, useCount: newCount)

        evictIfNeeded()
        persist()
    }

    /// O(k) prefix lookup via trie.
    func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        return trie.bestMatch(for: prefix, excluding: prefix)
    }

    // MARK: - Private

    private func evictIfNeeded() {
        while entriesMap.count > maxHistory {
            guard let oldest = recencyOrder.last else { break }
            recencyOrder.removeLast()
            entriesMap.removeValue(forKey: oldest)
            trie.remove(text: oldest)
        }
    }

    private func load() {
        // Migration: old string-array format.
        if let legacy = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            for text in legacy {
                entriesMap[text] = 1
            }
            recencyOrder = legacy
            trie.rebuild(from: entriesMap)
            persist()
            return
        }

        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data)
        else {
            // Try bare [Entry] from previous version.
            if let data = UserDefaults.standard.data(forKey: defaultsKey),
               let bare = try? JSONDecoder().decode([Entry].self, from: data) {
                for e in bare { entriesMap[e.text] = e.useCount }
                recencyOrder = bare.map(\.text)
                trie.rebuild(from: entriesMap)
                persist()
            }
            return
        }

        for e in stored.entries { entriesMap[e.text] = e.useCount }
        recencyOrder = stored.recencyOrder
        trie.rebuild(from: entriesMap)
    }

    private func persist() {
        let entries = entriesMap.map { Entry(text: $0.key, useCount: $0.value) }
        let stored = StoredData(entries: entries, recencyOrder: recencyOrder)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private struct StoredData: Codable {
        var entries: [Entry]
        var recencyOrder: [String]
    }
}
