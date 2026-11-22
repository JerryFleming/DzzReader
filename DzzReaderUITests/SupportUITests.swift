import XCTest

/// The 支持 tab: four voluntary tips sold as consumable in-app purchases. The test runner gets no
/// StoreKit configuration, so this checks the layout and the fallback prices.
final class SupportUITests: XCTestCase {
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

    func testTipsListedWithPrices() {
        let tab = app.tabBars.firstMatch.buttons["支持"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let expected = ["小小心意": "0.99", "请杯咖啡": "2.99", "支持一下": "4.99", "慷慨支持": "9.99"]
        for (title, price) in expected {
            let row = app.buttons["tip-\(title)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "missing \(title)")
            XCTAssertTrue(row.label.contains(price), "\(title) shows \(row.label)")
        }
        saveShot("support")
        // Products only load under the scheme's Run action (StoreKit configuration); purchases are
        // covered in-process by DzzReaderTests/TipJarTests.
    }
}
