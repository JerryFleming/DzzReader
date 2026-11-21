import XCTest

final class ReaderChromeUITests: XCTestCase {
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

    func openChangAhan() {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("0001")
        let row = app.collectionViews["shelfSearchResults"].staticTexts["0001 · 长阿含经"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
        sleep(1)
    }

    func showChrome() {
        if !app.staticTexts["chapterTitle"].exists {
            app.textViews["chapterText"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        }
    }

    /// The 繁/简 button shows the book in the other script and back, keeps the place, and converts titles.
    func testScriptButtonConvertsTheBook() {
        openChangAhan()
        showChrome()
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)   // the chapter list is lazy
        sleep(1)
        app.buttons["chaptersButton"].tap()
        XCTAssertTrue(app.buttons["chapter-3"].waitForExistence(timeout: 5))
        app.buttons["chapter-3"].tap()
        let title = app.staticTexts["chapterTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "佛说长阿含经卷第三")
        let text = app.textViews["chapterText"]
        let before = text.value as? String ?? ""
        XCTAssertFalse(before.isEmpty)

        let button = app.buttons["scriptButton"]
        XCTAssertEqual(button.label, "转为繁体")
        button.tap()
        XCTAssertEqual(title.label, "佛說長阿含經卷第三")
        XCTAssertEqual(button.label, "转为简体")
        let after = text.value as? String ?? ""
        // The same lines on screen, now in traditional characters.
        XCTAssertEqual(after.utf16.count, before.utf16.count, "same place, same length")
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(after.applyingTransform(StringTransform("Hant-Hans"), reverse: false), before)
        saveShot("reader-traditional")

        app.buttons["chaptersButton"].tap()
        XCTAssertTrue(app.buttons["chapter-3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chapter-3"].label, "佛說長阿含經卷第三")
        app.buttons["chapter-3"].tap()

        // Back to simplified (other tests expect it).
        showChrome()
        button.tap()
        XCTAssertEqual(title.label, "佛说长阿含经卷第三")
        XCTAssertEqual(button.label, "转为繁体")
    }

    func testChapterListSliderAppearanceAndBookmarks() {
        openChangAhan()
        showChrome()

        // Start from the beginning regardless of progress persisted by earlier runs.
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)
        sleep(1)

        // Chapter list: 卷首 + 22 卷, jump to 卷第三.
        app.buttons["chaptersButton"].tap()
        XCTAssertTrue(app.buttons["chapter-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chapter-0"].label, "卷首")
        XCTAssertTrue(app.buttons["chapter-3"].waitForExistence(timeout: 5))
        saveShot("chapters")
        app.buttons["chapter-3"].tap()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chapterTitle"].label, "佛说长阿含经卷第三")

        // Slider: jump to about 80%; title changes and label shows the percent.
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0.8)
        sleep(1)
        let label = app.staticTexts["progressLabel"].label
        XCTAssertTrue(label.contains("%"), label)
        XCTAssertNotEqual(app.staticTexts["chapterTitle"].label, "佛说长阿含经卷第三")
        saveShot("slider-jumped")

        // Chapter list now shows 品 sections under the current 卷 (the world-system chapters near the end).
        app.buttons["chaptersButton"].tap()
        let anySection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'section-'")).firstMatch
        XCTAssertTrue(anySection.waitForExistence(timeout: 5))
        saveShot("chapters-sections")
        let sectionTitle = anySection.label
        anySection.tap()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        sleep(1)
        saveShot("section-jumped")
        // The text view reports only what is on screen, so the section heading must be in it.
        let visible = app.textViews["chapterText"].value as? String ?? ""
        XCTAssertTrue(visible.contains(sectionTitle.suffix(4)), "section \(sectionTitle) not at top of \(visible.prefix(60))")

        // Appearance: sepia + 宋体 + bigger font; reader stays put.
        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.buttons["护眼"].waitForExistence(timeout: 5))
        app.buttons["护眼"].tap()
        let songti = app.descendants(matching: .any).matching(NSPredicate(format: "label == '宋体'")).firstMatch
        XCTAssertTrue(songti.waitForExistence(timeout: 5))
        songti.tap()
        app.swipeUp()   // expand the sheet to its large detent so the sliders are on screen
        XCTAssertTrue(app.sliders["fontSizeSlider"].waitForExistence(timeout: 5))
        app.sliders["fontSizeSlider"].adjust(toNormalizedSliderPosition: 0.6)
        saveShot("appearance")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 5))
        saveShot("restyled")

        // Bookmarks: add from the toolbar, open the list, jump back to it.
        showChrome()
        let titleBefore = app.staticTexts["chapterTitle"].label
        app.buttons["bookmarkButton"].tap()
        // The confirmation toast is not exposed to the accessibility tree; the list below proves the bookmark exists.
        sleep(1)
        saveShot("after-bookmark-tap")
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)
        sleep(1)
        XCTAssertNotEqual(app.staticTexts["chapterTitle"].label, titleBefore)
        app.buttons["bookmarkListButton"].tap()
        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        saveShot("bookmarks")
        cell.tap()
        sleep(1)
        showChrome()
        XCTAssertEqual(app.staticTexts["chapterTitle"].label, titleBefore)

        // Kill and relaunch: same place, bookmark still there.
        let progress = app.staticTexts["progressLabel"].label
        app.terminate()
        app.launch()
        openChangAhan()
        showChrome()
        XCTAssertEqual(app.staticTexts["progressLabel"].label, progress)
        app.buttons["bookmarkListButton"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        saveShot("relaunched")
    }
}
