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

    /// The timeouts only bound failures, so they are generous: while the card animates, XCUITest
    /// can stall a single query for about 15 s waiting for the app to go idle, and a predicate
    /// that is already true then misses a shorter deadline.
    private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 40) -> Bool {
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
        XCTAssertTrue(wait(card, "value ENDSWITH '字号\((Int(size) ?? 0) + 1)'"), value(card))
        app.buttons["缩小字号"].tap()
        XCTAssertTrue(wait(card, "value ENDSWITH '字号\(size)'"), value(card))

        // 恢复示例 and 清空 sit in the middle of the button row, between 标线 and 缩小字号.
        let clear = app.buttons["清空"], reset = app.buttons["恢复示例"]
        let underline = app.buttons["标线"], smaller = app.buttons["缩小字号"]
        XCTAssertTrue(clear.exists && reset.exists)
        XCTAssertEqual(reset.frame.midY, underline.frame.midY, accuracy: 2, "same row")
        XCTAssertGreaterThan(reset.frame.minX, underline.frame.maxX)
        XCTAssertLessThan(clear.frame.maxX, smaller.frame.minX)
        XCTAssertEqual(reset.frame.minX - underline.frame.maxX, smaller.frame.minX - clear.frame.maxX, accuracy: 2,
                       "midway between playback and the size buttons")
        // Every control is at least Apple's 44pt minimum tap target.
        for name in ["开始", "标线", "恢复示例", "清空", "缩小字号", "放大字号", "图片"] {
            let frame = app.buttons[name].frame
            XCTAssertGreaterThanOrEqual(frame.width, 44, name)
            XCTAssertGreaterThanOrEqual(frame.height, 44, name)
        }
        saveShot("share-editor-buttons")

        app.buttons["图片"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "share sheet did not open")
        saveShot("share-sheet")

        // The card can be saved to the photo library (the first time, iOS asks for permission).
        let save = sheet.cells["保存图像"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "保存图像 is offered")
        save.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["允许访问", "允许", "Allow Access", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "the sheet closes once the picture is saved")
        XCTAssertEqual(app.state, .runningForeground)
        saveShot("share-saved")
    }
}
