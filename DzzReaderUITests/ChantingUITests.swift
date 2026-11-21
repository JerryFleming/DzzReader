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

    /// The 繁/简 button shows the text in the other script and back, keeps the place, and is remembered.
    func testScriptButtonConvertsBetweenSimplifiedAndTraditional() {
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        let title = app.descendants(matching: .any)["chantRow-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "大佛顶首楞严神咒")
        let pinyin = title.value as? String
        // The book writes 南無 in a simplified text; it is shown as written until the button is tapped.
        let mixed = app.descendants(matching: .any)["chantRow-2"]
        XCTAssertEqual(mixed.label, "南無楞严会上佛菩萨（3称）")

        showChrome()
        let button = app.buttons["chantScriptButton"]
        XCTAssertEqual(button.label, "转为繁体")
        button.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "大佛頂首楞嚴神咒")
        XCTAssertEqual(title.value as? String, pinyin, "pinyin unchanged")
        XCTAssertEqual(mixed.label, "南無楞嚴會上佛菩薩（3稱）")
        XCTAssertEqual(button.label, "转为简体")
        saveShot("chant-traditional")

        // Remembered when the text is opened again.
        app.buttons["chantBackButton"].tap()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "大佛頂首楞嚴神咒")

        // Back to simplified (other tests expect it).
        showChrome()
        button.tap()
        XCTAssertEqual(title.label, "大佛顶首楞严神咒")
        XCTAssertEqual(button.label, "转为繁体")
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

    /// Samples once a second that the row holding the highlight is on screen.
    private func highlightMisses(seconds: Int, tag: String) -> [String] {
        let highlight = app.descendants(matching: .any)["chantHighlight"]
        let screen = app.windows.firstMatch.frame
        var misses: [String] = []
        for second in 0..<seconds {
            sleep(1)
            let row = highlight.value as? String ?? "?"
            let element = app.descendants(matching: .any)["chantRow-\(row)"]
            let frame = element.exists ? element.frame : .null
            if !frame.intersects(screen) {
                misses.append("\(tag) t=\(second)s block \(highlight.label) row \(row) frame \(frame)")
                saveShot("chant-miss-\(tag)-\(second)")
            }
        }
        return misses
    }

    private func resumeByTappingText() {
        app.descendants(matching: .any)["chantText"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["chantBackButton"].waitForNonExistence(timeout: 5))
    }

    /// The highlight stays on screen after a 目录 jump and after starting from a manually scrolled position.
    func testAutoScrollKeepsHighlightOnScreen() {
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chantRow-0"].waitForExistence(timeout: 10))
        var misses: [String] = []

        // 1. Auto-scroll on, then jump far ahead with 目录.
        showChrome()
        app.buttons["chantAutoScrollButton"].tap()
        showChrome()
        app.buttons["chantContentsButton"].tap()
        let heart = app.buttons["般若波罗蜜多心经"]
        XCTAssertTrue(app.buttons["大佛顶首楞严神咒"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !heart.exists { app.swipeUp() }
        heart.tap()
        misses += highlightMisses(seconds: 8, tag: "contents")

        // 2. Stop, scroll by hand, start again.
        showChrome()
        app.buttons["chantAutoScrollButton"].tap()
        resumeByTappingText()
        for _ in 0..<10 { app.swipeUp(velocity: .fast) }
        sleep(2)
        showChrome()
        app.buttons["chantAutoScrollButton"].tap()
        misses += highlightMisses(seconds: 8, tag: "manual")

        // 3. Pause, change font size, resume.
        showChrome()
        app.buttons["chantLargerButton"].tap()
        app.buttons["chantLargerButton"].tap()
        resumeByTappingText()
        misses += highlightMisses(seconds: 8, tag: "font")

        XCTAssertTrue(misses.isEmpty, "highlight off screen:\n" + misses.joined(separator: "\n"))
    }


    /// Starting auto-scroll after scrolling by hand highlights the first block on screen, without scrolling.
    func testAutoScrollStartsAtFirstBlockOnScreen() {
        // Slowest speed (a block every 3 s), so the highlight is still on its first block when checked.
        app.terminate()
        app.launchArguments += ["-chant.autoSpeed", "20"]
        app.launch()
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chantRow-0"].waitForExistence(timeout: 10))
        let text = app.descendants(matching: .any)["chantText"].firstMatch
        for _ in 0..<4 { text.swipeUp() }
        // Leave a partly hidden row at the top.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
        sleep(2)

        showChrome()
        app.buttons["chantAutoScrollButton"].tap()
        let highlight = app.descendants(matching: .any)["chantHighlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        saveShot("chant-auto-start-first-block")
        let rowID = Int(highlight.value as? String ?? "") ?? -1
        XCTAssertGreaterThan(rowID, 5, "not the beginning of the book")
        let row = app.descendants(matching: .any)["chantRow-\(rowID)"]
        let screenTop = app.windows.firstMatch.frame.minY + 62   // below the status-bar band
        XCTAssertTrue(row.frame.intersects(app.windows.firstMatch.frame), "highlighted row is on screen")
        XCTAssertLessThan(row.frame.minY, screenTop + 200, "highlighted row is at the top of the screen")
        let previous = app.descendants(matching: .any)["chantRow-\(rowID - 1)"]
        if previous.exists {
            XCTAssertLessThan(previous.frame.minY, screenTop, "the row above does not start on screen")
        }
        let before = row.frame.minY
        sleep(1)
        XCTAssertEqual(row.frame.minY, before, accuracy: 4, "starting does not scroll the text")
        saveShot("chant-auto-start-on-screen")
    }
}
