import XCTest
@testable import PasteNext

final class ModelTests: XCTestCase {
    func testClassifiesLink() {
        XCTAssertEqual(ClipClassifier.classify("https://pastenow.app"), .link)
    }
    func testClassifiesHexColor() {
        XCTAssertEqual(ClipClassifier.classify("#5F2EEA"), .color)
        XCTAssertEqual(ClipClassifier.classify("#5F2EEAFF"), .color)
    }
    func testClassifiesCode() {
        XCTAssertEqual(ClipClassifier.classify("import UIKit\nclass ViewController {\n}"), .code)
    }
    func testOrdinarySentenceIsText() {
        XCTAssertEqual(ClipClassifier.classify("Hello, this is a simple text message."), .text)
    }
    func testStablePaletteIsDeterministic() {
        XCTAssertEqual(Palette.color(for: "same"), Palette.color(for: "same"))
    }
    func testPinnedCategory() {
        var item = ClipItem(kind: .text, text: "hello")
        item.isPinned = true
        XCTAssertTrue(ClipCategory.pinned.contains(item))
        XCTAssertTrue(ClipCategory.all.contains(item))
        XCTAssertFalse(ClipCategory.code.contains(item))
    }
    func testHistoryRoundTrip() throws {
        let item = ClipItem(kind: .text, text: "持久化测试", isPinned: true)
        let data = try JSONEncoder.pasteNext.encode([item])
        let decoded = try JSONDecoder.pasteNext.decode([ClipItem].self, from: data)
        XCTAssertEqual(decoded.first?.text, item.text)
        XCTAssertEqual(decoded.first?.isPinned, true)
    }
}
