import XCTest

/// Needs `dzz-import-sample.txt` in the simulator's "On My iPhone" storage (planted by the test driver).
final class ImportUITests: XCTestCase {
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

    private func tapFirst(_ candidates: [XCUIElement], timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in candidates where element.exists && element.isHittable {
                element.tap()
                return true
            }
            usleep(300_000)
        }
        return false
    }

    func testImportsFromFilesAndDeletes() {
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        app.buttons["导入"].tap()
        sleep(3)
        saveShot("picker")

        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'dzz-import-sample'")).firstMatch
        if !file.waitForExistence(timeout: 5) {
            // Not in Recents: go to Browse → On My iPhone.
            _ = tapFirst([app.buttons["Browse"], app.buttons["浏览"], app.tabBars.buttons.element(boundBy: 1)])
            sleep(1)
            _ = tapFirst([app.staticTexts["On My iPhone"], app.staticTexts["我的 iPhone"], app.buttons["On My iPhone"], app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch])
            sleep(1)
            saveShot("picker-onmyiphone")
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), "sample file not visible in the picker")
        file.tap()
        // Multiple selection mode: the tap selects; confirm with Open.
        _ = tapFirst([app.buttons["Open"], app.buttons["打开"]], timeout: 5)

        // Single successful import opens the reader directly.
        XCTAssertTrue(app.textViews["chapterText"].waitForExistence(timeout: 20))
        app.textViews["chapterText"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["chapterTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chapterTitle"].label, "导入测试经卷上")
        XCTAssertTrue(app.staticTexts["progressLabel"].label.hasPrefix("1/2"))
        saveShot("imported-reader")

        // Back on the shelf it is listed under 导入的书; swipe to delete removes it.
        app.buttons["backButton"].tap()
        let rows = app.staticTexts.matching(identifier: "导入测试经")   // also listed under 最近阅读
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["导入的书"].exists)
        saveShot("shelf-imported")
        let before = rows.count
        rows.element(boundBy: before - 1).swipeLeft()   // the last one is in the 导入的书 section
        XCTAssertTrue(tapFirst([app.buttons["Delete"], app.buttons["删除"]], timeout: 5))
        sleep(1)
        XCTAssertLessThan(rows.count, before, "deleting removes the book from the shelf")   // recents is capped at 5, so the exact drop varies
        saveShot("shelf-after-delete")
    }
}
