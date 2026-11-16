import XCTest

/// Drives the real app on the simulator. Screenshots go to $TEST_RUNNER_DZZ_SHOTS when set.
final class ShelfUITests: XCTestCase {
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

    func testShelfListsSectionsAndOpensOne() {
        let agama = app.staticTexts["阿含部"]
        XCTAssertTrue(agama.waitForExistence(timeout: 30), "shelf did not load")
        saveShot("shelf")
        agama.tap()
        let first = app.staticTexts["0001 · 长阿含经"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        saveShot("section-agama")
        first.tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
    }

    func testSearchFindsByNumber() {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("0026")
        saveShot("search-typed")
        XCTAssertTrue(app.staticTexts["0026 · 中阿含经"].waitForExistence(timeout: 10))
        saveShot("search-0026")
    }

    /// The keyboard stays up while typing (and scrolling the results); only Enter dismisses it.
    func testSearchKeepsFocusUntilEnter() {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields["shelfSearchField"]
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        for (i, ch) in ["0", "0", "2"].enumerated() {
            app.typeText(ch)   // into whatever has focus: fails if the field lost it
            sleep(1)
            XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard gone after character \(i + 1)")
        }
        XCTAssertEqual(field.value as? String, "002")

        // Scrolling the results does not dismiss the keyboard either.
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '002'")).firstMatch.swipeUp()
        sleep(1)
        saveShot("after-scroll")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard dismissed by scrolling")
        saveShot("search-focused")

        // Enter dismisses it and keeps the query and results.
        app.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Enter did not dismiss the keyboard")
        XCTAssertEqual(field.value as? String, "002")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '002'")).firstMatch.exists)
    }

    func testTopSearchBarAndBottomTabs() {
        let agama = app.staticTexts["阿含部"]
        XCTAssertTrue(agama.waitForExistence(timeout: 30))
        saveShot("shelf-tabs")

        // Search box at the top, on the same row as the import button, above the shelf list.
        let field = app.searchFields["shelfSearchField"]
        let importButton = app.buttons["导入"]
        XCTAssertTrue(field.exists && importButton.exists)
        XCTAssertLessThan(field.frame.maxY, agama.frame.minY)
        XCTAssertLessThan(field.frame.maxX, importButton.frame.minX)
        XCTAssertLessThan(abs(field.frame.midY - importButton.frame.midY), 8)

        // Bottom bar: 书架, 诵经, 分享; the other two are placeholders for now.
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.exists)
        for name in ["书架", "诵经", "分享"] { XCTAssertTrue(tabs.buttons[name].exists, name) }
        XCTAssertGreaterThan(tabs.frame.minY, agama.frame.maxY)

        tabs.buttons["诵经"].tap()
        XCTAssertTrue(app.staticTexts["即将推出"].waitForExistence(timeout: 5))
        saveShot("tab-chanting")
        tabs.buttons["分享"].tap()
        XCTAssertTrue(app.staticTexts["即将推出"].waitForExistence(timeout: 5))
        tabs.buttons["书架"].tap()
        XCTAssertTrue(agama.waitForExistence(timeout: 5))

        // The reader is full screen: no tab bar while reading.
        agama.tap()
        let first = app.staticTexts["0001 · 长阿含经"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.exists, "tab bar stays on the 部 page")
        first.tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "tab bar hidden in the reader")
    }
}
