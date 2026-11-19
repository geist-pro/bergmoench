// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest

/// Walks a fresh collection through onboarding into Home, a review and the Reading page, at the default text size and
/// at a large accessibility size, and saves a screenshot of each step. The screens must stay usable at both sizes:
/// Study now reachable, grades on screen, nothing needed hidden.
/// Screenshots go to TEST_RUNNER_KARTEI_SHOTS=/some/folder (skipped when unset).
final class ReadingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDefaultSize() throws { try walk(size: nil, tag: "default") }
    func testAccessibilitySize() throws { try walk(size: "UICTContentSizeCategoryAccessibilityL", tag: "axl") }

    private func walk(size: String?, tag: String) throws {
        guard let shots = ProcessInfo.processInfo.environment["KARTEI_SHOTS"] else { throw XCTSkip("set TEST_RUNNER_KARTEI_SHOTS") }
        let data = NSTemporaryDirectory() + "kartei-ui-\(tag)-\(UUID().uuidString)"
        let app = XCUIApplication()
        app.launchEnvironment["KARTEI_DATA_DIR"] = data
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        func shot(_ name: String) {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: shots).appendingPathComponent("\(tag)-\(name).png"))
        }

        // Onboarding: pick the German course, add it, start.
        let gdp = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Grundlagen der Programmierung'")).firstMatch
        XCTAssertTrue(gdp.waitForExistence(timeout: 20))
        shot("01-onboarding")
        gdp.tap()
        let add = app.buttons["Add this course"].firstMatch
        if !add.isHittable { app.swipeUp() }
        add.tap()
        // Setup: the guided first session, then straight back home.
        let start = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Start with'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 90))
        if !start.isHittable { app.swipeUp() }
        start.tap()
        let back = app.buttons["Back to decks"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 20))
        back.tap()

        // Home: Study now must be on screen without scrolling.
        let study = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Study now'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 30))
        XCTAssertTrue(study.isHittable, "Study now is reachable")
        sleep(1)
        shot("02-home")

        // Review: question, answer, card actions.
        study.tap()
        let show = app.buttons["Show answer"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        sleep(2)
        shot("03-question")
        show.tap()
        let forgot = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Forgot'")).firstMatch
        XCTAssertTrue(forgot.waitForExistence(timeout: 10))
        XCTAssertTrue(forgot.isHittable, "grades are on screen")
        sleep(2)
        shot("04-answer")
        app.buttons["Card actions"].tap()
        XCTAssertTrue(app.buttons["Red flag"].waitForExistence(timeout: 5))
        app.buttons["Red flag"].tap()
        shot("05-flag-set")
        app.buttons["Close card actions"].firstMatch.tap()
        sleep(1)
        shot("06-flagged")
        app.buttons["Back to decks"].tap()

        // Settings › Reading.
        app.buttons["Settings"].tap()
        let reading = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Reading'")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        reading.tap()
        sleep(1)
        shot("07-reading")
    }
}
