import XCTest

/// Small books are one continuous document (chapters are positions); big ones load a chapter at a time
/// and change chapter when the reader pulls past the top or bottom edge.
final class ContinuousReadingUITests: XCTestCase {
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

    var chapterText: XCUIElement { app.textViews["chapterText"] }

    /// Opens a book by canon number and returns the seconds from tapping its row to the text appearing.
    @discardableResult
    func open(_ number: String) -> TimeInterval {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText(number)
        let row = app.collectionViews["shelfSearchResults"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "\(number) ·")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let start = Date()
        row.tap()
        XCTAssertTrue(chapterText.waitForExistence(timeout: 30))
        let seconds = Date().timeIntervalSince(start)
        print("DZZ-TIMING open \(number): \(String(format: "%.2f", seconds))s")
        sleep(1)
        return seconds
    }

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

    var chapterTitle: String { app.staticTexts["chapterTitle"].label }

    /// Picks chapter `index` in the 目录 sheet and returns its title.
    @discardableResult
    func jump(toChapter index: Int) -> String {
        showChrome()
        app.buttons["chaptersButton"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForExistence(timeout: 5))
        let row = app.buttons["chapter-\(index)"]
        // The list builds rows lazily; callers only jump forwards, so look downwards.
        var tries = 0
        // "Hittable" is also true for a row peeking out under the sheet's bottom edge; require it well on screen.
        let screenBottom = app.windows.firstMatch.frame.maxY - 80
        while !(row.exists && row.isHittable && row.frame.maxY < screenBottom) && tries < 15 {
            app.collectionViews.firstMatch.swipeUp()
            tries += 1
        }
        XCTAssertTrue(row.isHittable, "chapter-\(index) not reachable")
        if tries > 0 { sleep(1) }   // a tap on a still-coasting list only stops the scroll
        let title = row.label
        let start = Date()
        row.tap()
        if !app.navigationBars["目录"].waitForNonExistence(timeout: 10) { saveShot("jump-\(index)-sheet-stuck") }
        XCTAssertFalse(app.navigationBars["目录"].exists, "目录 still open after tapping chapter-\(index)")
        print("DZZ-TIMING jump chapter-\(index): \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        sleep(1)
        return title
    }

    /// Chapter count from the progress label ("3/27 · 9%").
    var chapterCount: Int {
        showChrome()
        let label = app.staticTexts["progressLabel"].label
        let total = label.split(separator: "·").first?.split(separator: "/").last ?? ""
        return Int(total.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// 1824 中观论疏: about 276K characters in many 卷, just under the whole-book cutoff.
    func testWholeBookJumpsAndScrollsAcrossChapters() {
        open("1824")
        let count = chapterCount
        XCTAssertGreaterThan(count, 6)
        // Progress is kept between runs; start from the beginning.
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0)
        sleep(1)

        let fifth = jump(toChapter: 5)
        hideChrome()
        saveShot("whole-jump-5")
        showChrome()
        XCTAssertTrue(chapterTitle == fifth, "expected \(fifth), got \(chapterTitle)")
        hideChrome()

        // Scrolling back a little from the start of 卷6 shows the end of 卷5 in the same document.
        chapterText.swipeDown()
        sleep(2)
        saveShot("whole-scrolled-back")
        showChrome()
        let fourth = vmChapterTitle(4)
        XCTAssertTrue(chapterTitle == fourth, "expected \(fourth), got \(chapterTitle)")

        // ...and scrolling forward again crosses back into 卷6 without any chapter swap.
        hideChrome()
        chapterText.swipeUp()
        chapterText.swipeUp()
        sleep(2)
        showChrome()
        XCTAssertTrue(chapterTitle == fifth, "expected \(fifth), got \(chapterTitle)")

        // A slider jump far past the laid-out text lands where asked (TextKit 2 only estimates unlaid heights).
        app.sliders["progressSlider"].adjust(toNormalizedSliderPosition: 0.8)
        sleep(1)
        let label = app.staticTexts["progressLabel"].label
        let percent = Int(label.split(separator: "·").last?.filter(\.isNumber) ?? "") ?? -1
        XCTAssertTrue(abs(percent - 80) <= 5, "slider to 80% landed at \(label)")

        // A long jump to the last chapter, far past anything laid out so far, lands there and stays.
        let last = jump(toChapter: count - 1)
        hideChrome()
        saveShot("whole-jump-last")
        showChrome()
        XCTAssertTrue(chapterTitle == last, "expected \(last), got \(chapterTitle)")
    }

    /// Title of chapter `index` as listed in the 目录 sheet.
    func vmChapterTitle(_ index: Int) -> String {
        showChrome()
        app.buttons["chaptersButton"].tap()
        let row = app.buttons["chapter-\(index)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let title = row.label
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["目录"].waitForNonExistence(timeout: 5))
        return title
    }

    /// 1828 瑜伽论记: about 918K characters, so it is shown a chapter at a time.
    func testLargeBookPullsPastEdgesToChangeChapter() {
        open("1828")
        let second = jump(toChapter: 2)
        let first = vmChapterTitle(1)
        hideChrome()

        // Pull down at the top of 卷3: opens the previous chapter at its last screen.
        let top = chapterText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let bottom = chapterText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        top.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
        saveShot("large-pulled-down")
        showChrome()
        XCTAssertTrue(chapterTitle == first, "expected \(first), got \(chapterTitle)")
        hideChrome()

        // Pull up at the bottom of that chapter: back to the start of the next one.
        bottom.press(forDuration: 0.1, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
        saveShot("large-pulled-up")
        showChrome()
        XCTAssertTrue(chapterTitle == second, "expected \(second), got \(chapterTitle)")
        hideChrome()

        // A previous-screen swipe on the first screen also goes back a chapter.
        chapterText.swipeRight()
        sleep(2)
        showChrome()
        XCTAssertTrue(chapterTitle == first, "expected \(first), got \(chapterTitle)")
    }
}
