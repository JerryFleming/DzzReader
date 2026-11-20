import XCTest

/// The 诵经 tab: a shelf of chanting texts, a pinyin reader, and recently read texts.
final class ChantingUITests: XCTestCase {
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

    private func openChantTab() {
        let tab = app.tabBars.firstMatch.buttons["诵经"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.buttons["chantImportButton"].waitForExistence(timeout: 5))
    }

    private func showChrome() {
        app.descendants(matching: .any)["chantText"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["chantBackButton"].waitForExistence(timeout: 5))
    }

    func testBundledTextOpensWithPinyinAtTheStart() {
        openChantTab()
        let shelf = app.collectionViews["chantShelf"]
        let book = shelf.staticTexts["佛教念诵集"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        saveShot("chant-shelf")
        book.tap()

        let title = app.descendants(matching: .any)["chantRow-0"]
        let opened = Date()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertLessThan(Date().timeIntervalSince(opened), 3, "text took too long to appear")
        XCTAssertEqual(title.label, "大佛顶首楞严神咒")
        XCTAssertTrue((title.value as? String ?? "").hasPrefix("dà fó dǐng shǒu léng yán shén zhòu"))
        saveShot("chant-reader-top")

        // Scroll a few screens, then leave.
        for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["chantRow-0"].isHittable, "scrolled past the title")
        showChrome()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '%'")).firstMatch.exists, "no progress shown")
        saveShot("chant-reader-chrome")

        // The theme button flips between light and dark, and back.
        let themeButton = app.buttons["chantThemeButton"]
        let before = themeButton.label
        themeButton.tap()
        XCTAssertNotEqual(themeButton.label, before)
        saveShot("chant-reader-theme-toggled")
        themeButton.tap()
        XCTAssertEqual(themeButton.label, before)

        // Back on the shelf it is under 最近阅读, without a percentage; after relaunch it opens at the start again.
        app.buttons["chantBackButton"].tap()
        XCTAssertTrue(app.staticTexts["最近阅读"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.collectionViews["chantShelf"].staticTexts.matching(NSPredicate(format: "label ENDSWITH '%'")).firstMatch.exists)
        saveShot("chant-shelf-recents")

        app.terminate()
        app.launch()
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chantRow-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["chantRow-0"].isHittable, "opens at the start")
        saveShot("chant-reader-reopened")
    }

    func testContentsJumpsToPassage() {
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chantText"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        showChrome()
        app.buttons["chantContentsButton"].tap()
        let heart = app.buttons["般若波罗蜜多心经"]
        XCTAssertTrue(app.buttons["大佛顶首楞严神咒"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !heart.exists { app.swipeUp() }   // the contents list is lazy
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        heart.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == '般若波罗蜜多心经'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        saveShot("chant-heart-sutra")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "tab bar hidden in the reader")
    }

    /// Auto-scroll moves a highlight block by block and scrolls to keep its line in the middle.
    func testAutoScrollHighlightsAndFollows() {
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        let title = app.descendants(matching: .any)["chantRow-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let titleTop = title.frame.minY

        showChrome()
        app.buttons["chantAutoScrollButton"].tap()
        let highlight = app.descendants(matching: .any)["chantHighlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        XCTAssertLessThan(Int(highlight.label) ?? 99, 8, "starts at the title (it may have moved a few blocks already)")

        // Pause to turn the speed up, then resume by tapping the text.
        showChrome()
        let slider = app.sliders["chantAutoSpeedSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(app.staticTexts["chantAutoSpeedLabel"].label, "300字/分")
        saveShot("chant-auto-paused")
        app.descendants(matching: .any)["chantText"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["chantBackButton"].waitForNonExistence(timeout: 5))

        // About 5 blocks a second. The middle of the screen is reached around block 100 (the 7th verse line);
        // after that the text moves up to keep the highlighted line there.
        sleep(30)
        let reached = Int(highlight.label) ?? 0
        XCTAssertGreaterThan(reached, 120)
        XCTAssertLessThan(title.exists ? title.frame.minY : -1, titleTop, "text scrolled to follow the highlight")
        saveShot("chant-auto-running")

        // Paused while the chrome shows: the highlight stays put.
        showChrome()
        let paused = highlight.label
        sleep(2)
        XCTAssertEqual(highlight.label, paused)

        // Stop clears the highlight.
        app.buttons["chantAutoScrollButton"].tap()
        XCTAssertTrue(highlight.waitForNonExistence(timeout: 5))
    }
}
