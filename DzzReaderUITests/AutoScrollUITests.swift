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
        let row = app.staticTexts["0172 · 佛说菩萨投身饴饿虎起塔因缘经"]
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
            XCTAssertTrue(app.buttons["pageDownButton"].waitForExistence(timeout: 5))
        }
    }

    /// Whole-book percentage from the progress label ("1/2 · 37%").
    func percent() -> Int {
        let label = app.staticTexts["progressLabel"].label
        let digits = label.split(separator: "·").last?.filter(\.isNumber) ?? ""
        return Int(digits) ?? -1
    }

    func testPageButtonsAndAutoScroll() {
        openShortBook()
        showChrome()
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)
        sleep(1)
        let start = percent()
        hideChrome()
        saveShot("page-buttons")

        // Next screen twice, then back twice.
        app.buttons["pageDownButton"].tap()
        sleep(1)
        app.buttons["pageDownButton"].tap()
        sleep(1)
        saveShot("paged-down")
        showChrome()
        let paged = percent()
        XCTAssertGreaterThan(paged, start)
        hideChrome()
        app.buttons["pageUpButton"].tap()
        sleep(1)
        app.buttons["pageUpButton"].tap()
        sleep(1)
        showChrome()
        XCTAssertLessThan(percent(), paged)

        // Auto-scroll: starting hides the chrome; tapping the centre pauses and shows the speed control.
        app.buttons["autoScrollButton"].tap()
        XCTAssertTrue(app.buttons["pageDownButton"].waitForExistence(timeout: 5))
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

        // The appearance toggle hides the page buttons.
        app.buttons["appearanceButton"].tap()
        let toggle = app.switches["pageButtonsToggle"]
        revealToggle(toggle)
        saveShot("appearance-toggle")
        toggle.switches.firstMatch.tap()
        app.buttons["完成"].tap()
        hideChrome2()
        XCTAssertFalse(app.buttons["pageDownButton"].exists)
        // Restore the default for other runs.
        showChrome()
        app.buttons["appearanceButton"].tap()
        revealToggle(toggle)
        toggle.switches.firstMatch.tap()
        app.buttons["完成"].tap()
    }

    /// The toggle sits at the bottom of the appearance sheet: expand the sheet, then scroll its list.
    func revealToggle(_ toggle: XCUIElement) {
        for _ in 0..<4 where !(toggle.exists && toggle.isHittable) {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    /// Hide the chrome when the page buttons are switched off (nothing to wait for).
    func hideChrome2() {
        if app.staticTexts["chapterTitle"].exists {
            tapCenter()
            sleep(1)
        }
        XCTAssertFalse(app.staticTexts["chapterTitle"].exists)
    }
}
