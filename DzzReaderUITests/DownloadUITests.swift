import XCTest

/// Downloads add to the shelf: a small archive with no toc.txt lands in the unnamed group beside the
/// dzz 部 (fetched from GitHub first if missing), and that group can then be deleted. Needs network
/// access the first time, and `TEST_RUNNER_DZZ_TOCLESS` set to the path of a toc-less .tar.gz holding
/// 念佛.txt and sub/心经.txt.
final class DownloadUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func download(_ url: String?) {
        let button = app.buttons["downloadBooks"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
        let field = app.descendants(matching: .any)["downloadURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        if let url {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.95)).tap()   // caret at the end
            let current = (field.value as? String) ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
            field.typeText(url)
        } else if app.buttons["恢复默认网址"].exists {
            app.buttons["恢复默认网址"].tap()
        }
        app.buttons["startDownload"].tap()
        // The sheet closes once the books are installed and catalogued.
        XCTAssertTrue(field.waitForNonExistence(timeout: 300), "download did not finish")
    }

    func testDownloadAddsBooksAndGroupsCanBeDeleted() throws {
        let tocless = try XCTUnwrap(ProcessInfo.processInfo.environment["DZZ_TOCLESS"], "set TEST_RUNNER_DZZ_TOCLESS")
        if !app.staticTexts["阿含部"].waitForExistence(timeout: 10) {
            download(nil)   // the dzz corpus from GitHub
            XCTAssertTrue(app.staticTexts["阿含部"].waitForExistence(timeout: 10))
        }

        // An archive without toc.txt goes into the unnamed group, beside the 部 already there.
        download(URL(fileURLWithPath: tocless).absoluteString)
        let nianfo = app.staticTexts["念佛"]
        // The unnamed group is at the bottom, below the 部. Drag from the empty right edge: a swipe that
        // starts on a row can register as a tap.
        let window = app.windows.firstMatch
        for _ in 0..<30 where !(nianfo.exists && nianfo.isHittable) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2)),
                       withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(nianfo.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["心经"].exists)
        let anySection = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'section-range-'")).firstMatch
        XCTAssertTrue(anySection.exists, "existing books must be kept")   // the 部 just above the unnamed group

        // Delete the whole unnamed group from a row's menu.
        nianfo.press(forDuration: 1.0)
        let groupDelete = app.buttons["删除整组"]
        XCTAssertTrue(groupDelete.waitForExistence(timeout: 5))
        groupDelete.tap()
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(nianfo.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["心经"].exists)
        XCTAssertTrue(anySection.exists)
    }
}
