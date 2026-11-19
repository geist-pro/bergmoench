// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

/// Swipe to grade: which grade a drag points at and when letting go grades.
final class SwipeGradeTests: XCTestCase {
    private let size = CGSize(width: 350, height: 500)

    private func prefs(easy: Bool = false, hard: Bool = false) -> TouchPrefs {
        let p = TouchPrefs(defaults: UserDefaults(suiteName: "swipe-\(UUID().uuidString)")!)
        p.swipeEasy = easy; p.swipeHard = hard
        return p
    }

    func testDefaults() {
        let p = prefs()
        XCTAssertTrue(p.swipeToGrade); XCTAssertFalse(p.swipeEasy); XCTAssertFalse(p.swipeHard); XCTAssertTrue(p.tapToReveal)
    }

    func testRightIsGoodLeftIsForgotPastAThird() {
        let p = prefs()
        XCTAssertEqual(SwipeGrade.release(CGSize(width: 130, height: 10), size: size, detail: .simple, prefs: p), .good)
        XCTAssertEqual(SwipeGrade.release(CGSize(width: -130, height: 10), size: size, detail: .simple, prefs: p), .forgot)
        XCTAssertNil(SwipeGrade.release(CGSize(width: 90, height: 0), size: size, detail: .simple, prefs: p), "short swipe springs back")
    }

    func testVerticalOnlyInFullAndWhenSwitchedOn() {
        let up = CGSize(width: 5, height: -150), down = CGSize(width: 5, height: 150)
        XCTAssertNil(SwipeGrade.release(up, size: size, detail: .full, prefs: prefs()), "Easy is off by default")
        XCTAssertNil(SwipeGrade.release(up, size: size, detail: .simple, prefs: prefs(easy: true)), "Simple has no Easy")
        XCTAssertEqual(SwipeGrade.release(up, size: size, detail: .full, prefs: prefs(easy: true)), .easy)
        XCTAssertNil(SwipeGrade.release(down, size: size, detail: .full, prefs: prefs(easy: true)), "Hard stays off")
        XCTAssertEqual(SwipeGrade.release(down, size: size, detail: .full, prefs: prefs(hard: true)), .hard)
    }

    func testProgressAndLabels() {
        XCTAssertEqual(SwipeGrade.progress(CGSize(width: 58, height: 0), size: size, rating: .good), 0.5, accuracy: 0.01)
        XCTAssertEqual(SwipeGrade.progress(CGSize(width: 400, height: 0), size: size, rating: .good), 1)
        XCTAssertEqual(SwipeGrade.label(.good, detail: .simple), "Got it")
        XCTAssertEqual(SwipeGrade.label(.good, detail: .full), "Good")
    }
}
