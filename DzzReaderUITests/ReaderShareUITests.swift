import XCTest

/// Selecting text in the reader and sending it to the 分享 card.
final class ReaderShareUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // No -share.quote here: an argument-domain value would hide what the reader writes.
        app.launchArguments += ["-shareTickMs", "150"]
        app.launch()
    }

    func saveShot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["DZZ_SHOTS"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSelectionIsSharedToTheQuoteCard() {
        let agama = app.staticTexts["阿含部"]
        XCTAssertTrue(agama.waitForExistence(timeout: 30))
        agama.tap()
        let first = app.staticTexts["0001 · 长阿含经"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        let text = app.textViews["chapterText"]
        XCTAssertTrue(text.waitForExistence(timeout: 20))

        // Long-press selects a word and brings up the edit menu.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.2)
        let share = app.descendants(matching: .any).matching(identifier: "分享卡片").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5), "no 分享卡片 in the edit menu")
        saveShot("reader-share-menu")
        share.tap()

        // The 分享 tab opens with 书名•卷名::文字 in the box and on the card.
        let card = app.otherElements["quoteCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.hasPrefix("长阿含经•"), card.label)
        let editor = app.textViews["quoteEditor"]
        let markup = editor.value as? String ?? ""
        XCTAssertTrue(markup.hasPrefix("长阿含经•"), markup)
        XCTAssertTrue(markup.contains("::"), markup)
        XCTAssertGreaterThan(markup.components(separatedBy: "::").last?.count ?? 0, 0, markup)
        saveShot("reader-share-card")

        // The book is still open under the 书架 tab.
        app.tabBars.firstMatch.buttons["书架"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 5))
    }
}
