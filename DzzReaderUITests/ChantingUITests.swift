import XCTest

/// The 诵经 tab: a shelf of chanting texts, a pinyin reader, and remembered position across launches.
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

    private func topVisibleRowID() -> Int? {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'chantRow-'"))
        let ids = rows.allElementsBoundByIndex.filter { $0.isHittable }
            .compactMap { Int($0.identifier.dropFirst("chantRow-".count)) }
        return ids.min()
    }

    func testBundledTextOpensWithPinyinAndRemembersPosition() {
        openChantTab()
        let shelf = app.collectionViews["chantShelf"]
        let book = shelf.staticTexts["佛教念诵集"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        saveShot("chant-shelf")
        book.tap()

        XCTAssertTrue(app.descendants(matching: .any)["chantText"].firstMatch.waitForExistence(timeout: 10))
        let title = app.descendants(matching: .any)["chantRow-0"]
        // Fresh simulators start at the top; later runs resume, so go to the start through the contents.
        showChrome()
        app.buttons["chantContentsButton"].tap()
        let first = app.buttons["大佛顶首楞严神咒"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "大佛顶首楞严神咒")
        XCTAssertTrue((title.value as? String ?? "").hasPrefix("dà fó dǐng shǒu léng yán shén zhòu"))
        saveShot("chant-reader-top")

        // Scroll a few screens, then check the chrome reports progress.
        for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        sleep(1)
        let reached = topVisibleRowID() ?? 0
        XCTAssertGreaterThan(reached, 5)
        saveShot("chant-reader-scrolled")
        showChrome()
        XCTAssertNotEqual(app.staticTexts["chantProgressLabel"].label, "0%")
        saveShot("chant-reader-chrome")

        // Back on the shelf it is under 最近阅读; after relaunch it reopens where it was.
        app.buttons["chantBackButton"].tap()
        XCTAssertTrue(app.staticTexts["最近阅读"].waitForExistence(timeout: 5))
        saveShot("chant-shelf-recents")

        app.terminate()
        app.launch()
        openChantTab()
        app.collectionViews["chantShelf"].staticTexts["佛教念诵集"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chantText"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        let resumed = topVisibleRowID() ?? 0
        XCTAssertLessThan(abs(resumed - reached), 3, "resumed at row \(resumed), left at \(reached)")
        saveShot("chant-reader-resumed")
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
}
