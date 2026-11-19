// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest

/// Swiping a deck row left reveals Delete instead of opening the deck; Delete asks before anything goes.
/// Needs a collection with decks: TEST_RUNNER_KARTEI_UI_DATA=/path/to/collection-folder (a copy; it is not changed).
final class SwipeDeleteUITests: XCTestCase {
    func testSwipeRevealsDeleteAndAsks() throws {
        guard let data = ProcessInfo.processInfo.environment["KARTEI_UI_DATA"] else { throw XCTSkip("set TEST_RUNNER_KARTEI_UI_DATA") }
        let app = XCUIApplication()
        app.launchEnvironment["KARTEI_DATA_DIR"] = data
        app.launch()
        let row = app.staticTexts["01 Times tables"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "swipe reveals Delete")
        XCTAssertFalse(app.buttons["Show answer"].exists, "the swipe did not open the deck")
        delete.tap()
        XCTAssertTrue(app.buttons["Delete deck"].waitForExistence(timeout: 3), "Delete asks first")
        // The action sheet's Cancel lives outside the app's button tree on iPhone; dismiss by tapping above the sheet.
        let cancel = app.descendants(matching: .any).matching(identifier: "Cancel").firstMatch
        if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap() }
        XCTAssertTrue(app.staticTexts["01 Times tables"].waitForExistence(timeout: 3), "Cancel keeps the deck")
        // A plain tap still opens the deck.
        app.staticTexts["02 Squares"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 10) || app.staticTexts["Back to decks"].exists
                      || app.buttons["Back to decks"].waitForExistence(timeout: 5), "tap opens the deck")
    }
}
