import XCTest

final class AutoScrollUITests: XCTestCase {
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

    /// A short one-卷 text, so a single screen moves the whole-book percentage visibly.
    func openShortBook() {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("0172")
        let row = app.collectionViews["shelfSearchResults"].staticTexts["0172 · 佛说菩萨投身饴饿虎起塔因缘经"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
        sleep(1)
    }

    var chapterText: XCUIElement { app.textViews["chapterText"] }

    func tapCenter() {
        chapterText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func showChrome() {
        if !app.staticTexts["chapterTitle"].exists {
            tapCenter()
            XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        }
    }

    func hideChrome() {
        if app.staticTexts["chapterTitle"].exists {
            tapCenter()
            XCTAssertTrue(app.staticTexts["chapterTitle"].waitForNonExistence(timeout: 5))
        }
    }

    /// Whole-book percentage from the progress label ("1/2 · 37%").
    func percent() -> Int {
        let label = app.staticTexts["progressLabel"].label
        let digits = label.split(separator: "·").last?.filter(\.isNumber) ?? ""
        return Int(digits) ?? -1
    }

    func testSwipePagingAndAutoScroll() {
        openShortBook()
        showChrome()
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)
        sleep(1)
        let start = percent()
        hideChrome()
        saveShot("before-swipe")

        // No page buttons any more; swipe left twice for the next screens, then right twice to go back.
        XCTAssertFalse(app.buttons["pageDownButton"].exists)
        chapterText.swipeLeft()
        sleep(1)
        saveShot("paged-1")   // its top line should be the bottom line of before-swipe
        chapterText.swipeLeft()
        sleep(1)
        saveShot("paged-down")
        showChrome()
        let paged = percent()
        XCTAssertGreaterThan(paged, start)
        hideChrome()
        chapterText.swipeRight()
        sleep(1)
        saveShot("paged-back-1")   // its bottom line should be the top line of paged-down
        chapterText.swipeRight()
        sleep(1)
        showChrome()
        XCTAssertLessThan(percent(), paged)

        // Auto-scroll: starting hides the chrome; tapping the centre pauses and shows the speed control.
        app.buttons["autoScrollButton"].tap()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForNonExistence(timeout: 5))
        showChrome()
        let speedSlider = app.sliders["autoScrollSpeedSlider"]
        XCTAssertTrue(speedSlider.waitForExistence(timeout: 5))
        // Go fast so a few seconds move the whole-book percentage.
        let speedBefore = app.staticTexts["autoScrollSpeedLabel"].label
        speedSlider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertNotEqual(app.staticTexts["autoScrollSpeedLabel"].label, speedBefore)
        let beforeAuto = percent()
        hideChrome()
        sleep(5)
        showChrome()
        XCTAssertGreaterThan(percent(), beforeAuto)
        let paused = percent()
        sleep(2)
        XCTAssertEqual(percent(), paused, "auto-scroll should pause while the chrome is shown")
        saveShot("auto-scroll-paused")
        speedSlider.adjust(toNormalizedSliderPosition: 0.17)   // back to about the default 30
        app.buttons["autoScrollButton"].tap()   // stop
        XCTAssertFalse(app.sliders["autoScrollSpeedSlider"].exists)
    }
}
