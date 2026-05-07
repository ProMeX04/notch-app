import XCTest
@testable import Notch

final class SpotlightManagerTests: XCTestCase {
    var manager: SpotlightManager!

    override func setUp() {
        super.setUp()
        manager = SpotlightManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testSearchSafariApp() {
        let results = manager.search(query: "Safari", limit: 5, scope: "applications", kind: "app")
        
        XCTAssertTrue(results["success"] as? Bool ?? false, "Search should be successful")
        let items = results["results"] as? [[String: Any]] ?? []
        
        XCTAssertFalse(items.isEmpty, "Should find at least one result for 'Safari'")
        
        let hasSafari = items.contains { item in
            let name = item["name"] as? String ?? ""
            return name.localizedCaseInsensitiveContains("Safari")
        }
        XCTAssertTrue(hasSafari, "Results should contain Safari")
    }

    func testSearchDocuments() {
        // This test assumes there's at least one document or folder in the user's home/documents.
        // We'll search for common terms.
        let results = manager.search(query: "test", limit: 10, scope: "home", kind: "any")
        
        XCTAssertTrue(results["success"] as? Bool ?? false, "Search should be successful")
        // We don't strictly assert non-empty here as it depends on user's files,
        // but we print it for debugging.
        let items = results["results"] as? [[String: Any]] ?? []
        print("Found \(items.count) results for 'test' in home")
        for item in items {
            print("- \(item["name"] ?? "Unknown"): \(item["path"] ?? "")")
        }
    }

    func testSearchWithKindFilter() {
        let results = manager.search(query: ".", limit: 20, scope: "applications", kind: "app")
        
        XCTAssertTrue(results["success"] as? Bool ?? false)
        let items = results["results"] as? [[String: Any]] ?? []
        
        for item in items {
            let path = item["path"] as? String ?? ""
            XCTAssertTrue(path.hasSuffix(".app"), "All results should be apps when kind is 'app'. Path: \(path)")
        }
    }

    func testEmptyQuery() {
        let results = manager.search(query: "", limit: 10, scope: "all", kind: "any")
        XCTAssertFalse(results["success"] as? Bool ?? true, "Search with empty query should fail")
    }
}
