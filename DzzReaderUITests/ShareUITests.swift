import XCTest

/// The 分享 tab: the quote card from lecture/index.html.
final class ShareUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A faster tick and a fixed quote. Argument-domain defaults win over saved ones, so the
        // font size is left alone: A+/A- must be able to change it.
        app.launchArguments += ["-shareTickMs", "150",
                                "-share.quote", "大乘经::善男子。|初发意|，何以故。"]
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

    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

    func testQuoteCardAnimatesAndShares() {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 30))
        tabs.buttons["分享"].tap()

        let card = app.otherElements["quoteCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(value(card).hasPrefix("写出9/9 标线3/3 出处显示"), "idle card shows the finished quote: \(value(card))")
        let size = value(card).components(separatedBy: "字号").last ?? ""
        XCTAssertTrue(app.textViews["quoteEditor"].exists)
        saveShot("share-idle")

        app.buttons["开始"].tap()
        // Writing starts from an empty, unsigned card.
        XCTAssertTrue(value(card).contains("出处隐藏"), value(card))
        XCTAssertFalse(value(card).hasPrefix("写出9/9"), value(card))

        XCTAssertTrue(wait(card, "value CONTAINS '出处显示'"), value(card))
        XCTAssertTrue(wait(card, "value BEGINSWITH '写出9/9 标线3/3 出处显示'"), value(card))
        saveShot("share-finished")

        app.buttons["放大字号"].tap()
        XCTAssertTrue(wait(card, "value ENDSWITH '字号\((Int(size) ?? 0) + 1)'", timeout: 3), value(card))
        app.buttons["缩小字号"].tap()
        XCTAssertTrue(wait(card, "value ENDSWITH '字号\(size)'", timeout: 3), value(card))

        app.buttons["图片"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "share sheet did not open")
        saveShot("share-sheet")
    }
}
