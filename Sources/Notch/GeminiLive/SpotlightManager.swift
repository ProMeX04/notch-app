import Foundation
import AppKit

/// A high-performance native macOS Spotlight search manager in Full Search Mode.
public final class SpotlightManager: NSObject, @unchecked Sendable {
    private let resultLock = NSLock()
    private var searchResult: [String: Any] = ["success": false, "error": "Search failed."]
    private var isCompleted = false
    private var currentSearchID: UUID = UUID()
    
    public override init() {
        super.init()
    }

    public func search(
        query rawQuery: String,
        limit: Int,
        scope: String?,
        kind: String?,
        timeout: TimeInterval = 6.0 // Increased for full search
    ) -> [String: Any] {
        let text = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ["success": false, "error": "Query is empty."] }

        let semaphore = DispatchSemaphore(value: 0)
        let searchID = UUID()
        let startTime = Date()
        
        resultLock.lock()
        self.isCompleted = false
        self.currentSearchID = searchID
        self.searchResult = ["success": false, "error": "Search timed out."]
        resultLock.unlock()

        let thread = Thread { [weak self] in
            guard let self = self else { semaphore.signal(); return }
            let query = NSMetadataQuery()
            query.searchScopes = self.searchScopes(for: scope ?? "home")
            query.predicate = self.buildPredicate(for: text, kind: kind ?? "any")
            
            let checkAndSignal = { (q: NSMetadataQuery, force: Bool) -> Bool in
                self.resultLock.lock()
                guard self.currentSearchID == searchID && !self.isCompleted else {
                    self.resultLock.unlock(); return true 
                }
                
                let results = self.extractAndRankResults(from: q, queryText: text, limit: limit)
                let bestScore = results.map { $0["score"] as? Int ?? 0 }.max() ?? 0
                let elapsed = Date().timeIntervalSince(startTime)
                
                // Full Search Exit Logic:
                // 1. Force exit (gathering finished or manual stop)
                // 2. Exact name match found (Score >= 1000) -> Exit early for UX
                // 3. Otherwise, keep gathering until the very end
                let hasExactMatch = bestScore >= 1000
                let gatheringDone = !q.isGathering
                
                let shouldExit = force || (hasExactMatch && elapsed > 0.5) || gatheringDone
                
                if shouldExit && (results.count > 0 || gatheringDone || force) {
                    self.searchResult = [
                        "success": true,
                        "results": results,
                        "count": results.count,
                        "query": text,
                        "duration": String(format: "%.2fs", elapsed)
                    ]
                    self.isCompleted = true
                    self.resultLock.unlock()
                    semaphore.signal()
                    return true
                }
                self.resultLock.unlock()
                return false
            }

            let center = NotificationCenter.default
            let obs = center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { n in
                if let q = n.object as? NSMetadataQuery { _ = checkAndSignal(q, true) }
            }

            if !query.start() {
                center.removeObserver(obs)
                self.resultLock.lock()
                if self.currentSearchID == searchID {
                    self.searchResult = ["success": false, "error": "Could not start query."]
                    self.isCompleted = true
                    semaphore.signal()
                }
                self.resultLock.unlock()
                return
            }

            let runLoop = RunLoop.current
            // Poll for exact matches or gathering finish
            while Date().timeIntervalSince(startTime) < timeout {
                if self.resultLock.withLock({ self.isCompleted || self.currentSearchID != searchID }) { break }
                if checkAndSignal(query, false) { break }
                runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }

            query.stop()
            center.removeObserver(obs)
            _ = checkAndSignal(query, true)
        }

        thread.start()
        _ = semaphore.wait(timeout: .now() + timeout + 0.5)
        
        resultLock.lock()
        let final = self.searchResult
        resultLock.unlock()
        return final
    }

    private func buildPredicate(for text: String, kind: String) -> NSPredicate {
        let terms = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var termPredicates: [NSPredicate] = []
        for term in terms {
            let p1 = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemDisplayNameKey, term)
            let p2 = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, term)
            let p3 = NSPredicate(format: "kMDItemTitle CONTAINS[cd] %@", term)
            let p4 = NSPredicate(format: "kMDItemTextContent CONTAINS[cd] %@", term)
            termPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [p1, p2, p3, p4]))
        }
        let base = termPredicates.count > 1 ? NSCompoundPredicate(andPredicateWithSubpredicates: termPredicates) : termPredicates[0]
        if kind == "any" { return base }
        let kindP = buildKindPredicate(for: kind)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, kindP])
    }

    private func buildKindPredicate(for kind: String) -> NSPredicate {
        switch kind {
        case "app": return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        case "folder": return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "public.folder")
        case "image": return NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, "public.image")
        case "pdf": return NSPredicate(format: "%K == %@", NSMetadataItemContentTypeKey, "com.adobe.pdf")
        case "audio": return NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, "public.audio")
        case "video": return NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, "public.movie")
        case "document": return NSPredicate(format: "ANY %K == %@", NSMetadataItemContentTypeTreeKey, "public.composite-content")
        default: return NSPredicate(value: true)
        }
    }

    private func extractAndRankResults(from query: NSMetadataQuery, queryText: String, limit: Int) -> [[String: Any]] {
        var scoredResults: [(score: Int, item: [String: Any])] = []
        let lowerQuery = queryText.lowercased()
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? URL(fileURLWithPath: path).lastPathComponent
            let lowerName = name.lowercased()
            
            var score = 0
            if lowerName == lowerQuery { score += 1000 }
            else if lowerName.hasPrefix(lowerQuery) { score += 500 }
            else if lowerName.contains(lowerQuery) { score += 100 }
            
            let contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String ?? ""
            if contentType == "com.apple.application-bundle" { score += 300 }
            else if contentType.contains("pdf") || contentType.contains("document") || contentType.contains("officedocument") {
                score += 400
            } else if contentType.contains("image") || contentType.contains("movie") {
                score -= 400
            }
            
            if path.contains("/node_modules/") || path.contains("/Library/") || path.contains(".log") || path.contains(".tmp") {
                score -= 900
            }
            scoredResults.append((score, ["name": name, "path": path, "score": score]))
        }
        return Array(scoredResults.sorted { $0.score > $1.score }.prefix(limit)).map { $0.item }
    }

    private func searchScopes(for scope: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch scope.lowercased() {
        case "all": return [NSMetadataQueryLocalComputerScope]
        case "applications": return ["/Applications", "/System/Applications"]
        case "documents": return [home.appendingPathComponent("Documents").path]
        case "desktop": return [home.appendingPathComponent("Desktop").path]
        case "downloads": return [home.appendingPathComponent("Downloads").path]
        default: return [NSMetadataQueryUserHomeScope]
        }
    }
}
extension NSLock { func withLock<T>(_ block: () -> T) -> T { self.lock(); defer { self.unlock() }; return block() } }
