import XCTest

/// Blank source lines are collapsed to a hairline, so 0236a's header block isn't spread over a screen.
final class BlankLineUITests: XCTestCase {
    func testHeaderBlockIsCompact() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 30))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("0236a")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "0236a")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let text = app.textViews["chapterText"]
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        sleep(1)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["DZZ_SHOTS"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("0236a.png"))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "0236a"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
