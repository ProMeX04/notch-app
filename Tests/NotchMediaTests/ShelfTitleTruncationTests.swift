import XCTest
import AppKit
@testable import Notch

final class ShelfTitleTruncationTests: XCTestCase {
    @MainActor
    func testShortTitleIsNotTruncated() {
        let view = ShelfCollectionItemView(frame: .zero)
        let font = NSFont.systemFont(ofSize: 9)
        let title = "archives" // 8 characters, <= 12
        let result = view.finderStyleMiddleTruncatedTitle(title, availableWidth: 100, font: font)
        XCTAssertEqual(result, "archives")
    }

    @MainActor
    func testLongTitleIsMiddleTruncated() {
        let view = ShelfCollectionItemView(frame: .zero)
        let font = NSFont.systemFont(ofSize: 9)
        // 21 characters, > 12
        let title = "my-very-long-file.txt"
        // Let's use a narrow width so that truncation is forced
        let result = view.finderStyleMiddleTruncatedTitle(title, availableWidth: 50, font: font)
        
        XCTAssertTrue(result.contains("..."), "Result should contain ellipsis: \(result)")
        XCTAssertTrue(result.hasPrefix("my"), "Result should start with prefix of stem: \(result)")
        XCTAssertTrue(result.hasSuffix(".txt") || result.hasSuffix("txt"), "Result should retain file extension: \(result)")
    }
}
