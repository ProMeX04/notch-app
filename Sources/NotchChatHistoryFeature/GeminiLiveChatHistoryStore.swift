import Combine
import Foundation

// MARK: - Trie for O(k) prefix lookup

/// Indexes lowercased text; each node tracks the best (most recently used) entry
/// in its subtree so prefix lookup is O(k) where k = prefix length.
private final class ChatHistoryTrie {
    final class Node {
        var children: [Character: Node] = [:]
        var terminalText: String?
        var terminalUseCount: Int = 0
        var terminalRecencyRank: Int = 0
        var subtreeBestText: String?
        var subtreeBestUseCount: Int = 0
        var subtreeBestRecencyRank: Int = 0
    }

    let root = Node()

    func insert(text: String, useCount: Int, recencyRank: Int) {
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
        node.terminalRecencyRank = recencyRank

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
        node.terminalRecencyRank = 0

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

        // Rare: best is the excluded text -> DFS for second-best.
        if excluding != nil {
            return dfsFindBest(node: node, excluding: excluding)
        }
        return nil
    }

    func rebuild(from entries: [String: Int], recencyRanks: [String: Int]) {
        root.children.removeAll()
        root.terminalText = nil
        root.terminalUseCount = 0
        root.terminalRecencyRank = 0
        root.subtreeBestText = nil
        root.subtreeBestUseCount = 0
        root.subtreeBestRecencyRank = 0
        for (text, count) in entries {
            insert(text: text, useCount: count, recencyRank: recencyRanks[text] ?? 0)
        }
    }

    // MARK: - Private

    private func recomputeSubtreeBest(_ node: Node) {
        var bestText: String? = node.terminalText
        var bestUseCount = node.terminalText != nil ? node.terminalUseCount : 0
        var bestRecencyRank = node.terminalText != nil ? node.terminalRecencyRank : 0

        for (_, child) in node.children {
            if child.subtreeBestText != nil,
               isBetter(
                recencyRank: child.subtreeBestRecencyRank,
                useCount: child.subtreeBestUseCount,
                thanRecencyRank: bestRecencyRank,
                thanUseCount: bestUseCount
               ) {
                bestText = child.subtreeBestText
                bestUseCount = child.subtreeBestUseCount
                bestRecencyRank = child.subtreeBestRecencyRank
            }
        }

        node.subtreeBestText = bestText
        node.subtreeBestUseCount = bestText != nil ? bestUseCount : 0
        node.subtreeBestRecencyRank = bestText != nil ? bestRecencyRank : 0
    }

    private func dfsFindBest(node: Node, excluding: String?) -> String? {
        var best: String?
        var bestUseCount = 0
        var bestRecencyRank = 0
        dfs(
            node: node,
            excluding: excluding,
            best: &best,
            bestUseCount: &bestUseCount,
            bestRecencyRank: &bestRecencyRank
        )
        return best
    }

    private func dfs(
        node: Node,
        excluding: String?,
        best: inout String?,
        bestUseCount: inout Int,
        bestRecencyRank: inout Int
    ) {
        if let t = node.terminalText,
           t != excluding,
           isBetter(
            recencyRank: node.terminalRecencyRank,
            useCount: node.terminalUseCount,
            thanRecencyRank: bestRecencyRank,
            thanUseCount: bestUseCount
           ) {
            best = t
            bestUseCount = node.terminalUseCount
            bestRecencyRank = node.terminalRecencyRank
        }
        for (_, child) in node.children {
            if child.subtreeBestText == excluding || isBetter(
                recencyRank: child.subtreeBestRecencyRank,
                useCount: child.subtreeBestUseCount,
                thanRecencyRank: bestRecencyRank,
                thanUseCount: bestUseCount
            ) {
                dfs(
                    node: child,
                    excluding: excluding,
                    best: &best,
                    bestUseCount: &bestUseCount,
                    bestRecencyRank: &bestRecencyRank
                )
            }
        }
    }

    private func isBetter(
        recencyRank: Int,
        useCount: Int,
        thanRecencyRank otherRecencyRank: Int,
        thanUseCount otherUseCount: Int
    ) -> Bool {
        if recencyRank != otherRecencyRank {
            return recencyRank > otherRecencyRank
        }
        return useCount > otherUseCount
    }
}

// MARK: - History Store

@MainActor
public final class GeminiLiveChatHistoryStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let defaultsKey: String
    private let maxHistory = 10_000

    struct Entry: Codable, Equatable {
        var text: String
        var useCount: Int
    }

    private var entriesMap: [String: Int] = [:]        // text -> useCount
    private var recencyRankMap: [String: Int] = [:]    // text -> monotonic recency rank
    private var nextRecencyRank: Int = 0
    @Published private(set) var recencyOrder: [String] = []
    private let trie = ChatHistoryTrie()

    public var history: [String] { recencyOrder }

    public static let shared = GeminiLiveChatHistoryStore()

    public init(
        userDefaults: UserDefaults = .standard,
        defaultsKey: String = "dev.notch.gemini-live-chat.history"
    ) {
        self.userDefaults = userDefaults
        self.defaultsKey = defaultsKey
        load()
    }

    // MARK: - Public API

    public func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Recency
        recencyOrder.removeAll { $0 == trimmed }
        recencyOrder.insert(trimmed, at: 0)

        // Frequency + recency-ranked trie.
        let oldCount = entriesMap[trimmed] ?? 0
        let newCount = oldCount + 1
        entriesMap[trimmed] = newCount
        nextRecencyRank += 1
        recencyRankMap[trimmed] = nextRecencyRank

        if oldCount > 0 { trie.remove(text: trimmed) }
        trie.insert(text: trimmed, useCount: newCount, recencyRank: nextRecencyRank)

        evictIfNeeded()
        persist()
    }

    /// O(k) prefix lookup via trie.
    public func getSuggestion(for prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        return trie.bestMatch(for: prefix, excluding: prefix)
    }

    // MARK: - Private

    private func evictIfNeeded() {
        while entriesMap.count > maxHistory {
            guard let oldest = recencyOrder.last else { break }
            recencyOrder.removeLast()
            entriesMap.removeValue(forKey: oldest)
            recencyRankMap.removeValue(forKey: oldest)
            trie.remove(text: oldest)
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(StoredData.self, from: data)
        else {
            return
        }

        for e in stored.entries { entriesMap[e.text] = e.useCount }
        recencyOrder = stored.recencyOrder
        rebuildRecencyRanksAndTrie()
    }

    private func persist() {
        let entries = entriesMap.map { Entry(text: $0.key, useCount: $0.value) }
        let stored = StoredData(entries: entries, recencyOrder: recencyOrder)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }

    private func rebuildRecencyRanksAndTrie() {
        normalizeRecencyOrder()

        recencyRankMap.removeAll()
        nextRecencyRank = 0

        for text in recencyOrder.reversed() {
            nextRecencyRank += 1
            recencyRankMap[text] = nextRecencyRank
        }

        trie.rebuild(from: entriesMap, recencyRanks: recencyRankMap)
    }

    private func normalizeRecencyOrder() {
        var seen = Set<String>()
        recencyOrder = recencyOrder.filter { text in
            guard entriesMap[text] != nil else { return false }
            return seen.insert(text).inserted
        }

        for text in entriesMap.keys where !seen.contains(text) {
            recencyOrder.append(text)
        }
    }

    private struct StoredData: Codable {
        var entries: [Entry]
        var recencyOrder: [String]
    }
}
