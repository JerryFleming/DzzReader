import XCTest

final class ReaderUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
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

    /// Opens a book from the shelf by searching its 经号.
    func openBook(number: String, rowTitle: String) {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(number)
        let row = app.collectionViews["shelfSearchResults"].staticTexts[rowTitle]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
    }

    func tapCenter() {
        app.textViews["chapterText"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testOpensNavigatesAndResumes() {
        openBook(number: "0001", rowTitle: "0001 · 长阿含经")
        let text = app.textViews["chapterText"]
        XCTAssertTrue(text.value as? String != nil)
        saveShot("reader-open")

        tapCenter()
        let title = app.staticTexts["chapterTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        saveShot("reader-chrome")

        app.buttons["nextChapter"].tap()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        let afterNext = app.staticTexts["chapterTitle"].label
        XCTAssertTrue(afterNext.contains("卷第"), "title after next: \(afterNext)")
        saveShot("reader-next")

        // Scroll a bit into the chapter, remember the first visible words.
        text.swipeUp()
        text.swipeUp()
        sleep(1)
        let progressBefore = app.staticTexts["progressLabel"].label
        let visibleBefore = (text.value as? String ?? "").prefix(12)
        saveShot("reader-scrolled")

        // Leave and come back.
        app.buttons["backButton"].tap()
        let row = app.collectionViews["shelfSearchResults"].staticTexts["0001 · 长阿含经"]   // the search is still open
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        sleep(1)
        tapCenter()
        XCTAssertTrue(app.staticTexts["progressLabel"].waitForExistence(timeout: 5))
        let progressAfter = app.staticTexts["progressLabel"].label
        XCTAssertEqual(progressBefore, progressAfter)
        XCTAssertEqual(visibleBefore, (text.value as? String ?? "").prefix(12))
        saveShot("reader-resumed")
    }

    /// The largest file in the corpus (5.3 MB, 0220c 大般若经) must open and show its 目录 promptly.
    func testLargestBookOpensQuickly() {
        let started = Date()
        openBook(number: "0220c", rowTitle: "0220c · 大般若波罗蜜多经")
        let opened = Date().timeIntervalSince(started)
        tapCenter()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        let sheetStart = Date()
        app.buttons["chaptersButton"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'chapter-'")).firstMatch.waitForExistence(timeout: 5))
        let sheetTime = Date().timeIntervalSince(sheetStart)
        saveShot("largest-chapters")
        NSLog("DZZPERF largest book open=%.2fs chapters sheet=%.2fs", opened, sheetTime)
        XCTAssertLessThan(sheetTime, 3.0)
        app.buttons["完成"].tap()
        app.textViews["chapterText"].swipeUp()
        app.textViews["chapterText"].swipeUp()
        XCTAssertTrue(app.textViews["chapterText"].exists)
    }

    func testEmptyAndSmallBooksOpen() {
        openBook(number: "0002", rowTitle: "0002 · 佛说七佛经")
        tapCenter()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nextChapter"].isEnabled)
        saveShot("reader-single-juan")
        app.buttons["backButton"].tap()

        // The one 0-byte file in the corpus (2722) must open without crashing and read 全书完.
        XCTAssertTrue(app.staticTexts["0002 · 佛说七佛经"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        field.typeText("2722")
        let row = app.collectionViews["shelfSearchResults"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2722 ·'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let text = app.textViews["chapterText"]
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        XCTAssertTrue((text.value as? String ?? "").contains("全书完"))
        tapCenter()
        XCTAssertTrue(app.staticTexts["progressLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["progressLabel"].label.hasSuffix("100%"))
        saveShot("reader-empty")
    }
}
