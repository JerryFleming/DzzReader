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
        XCTAssertTrue(app.staticTexts["0026 · 中阿含经"].waitForExistence(timeout: 10))
        saveShot("search-0026")
    }
}
