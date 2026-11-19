// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import XCTest
@testable import Kartei

final class CountdownTests: XCTestCase {
    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    func testCountdownWording() {
        XCTAssertNil(examCountdown(nil))
        XCTAssertNil(examCountdown(day(-1)))
        XCTAssertEqual(examCountdown(day(0)), "exam today")
        XCTAssertEqual(examCountdown(day(1)), "exam tomorrow")
        XCTAssertEqual(examCountdown(day(9)), "exam in 9 days")
        XCTAssertEqual(examCountdown(day(13)), "exam in 13 days")
        XCTAssertEqual(examCountdown(day(14)), "exam in 2 weeks")
        XCTAssertEqual(examCountdown(day(90)), "exam in 12 weeks")
    }
}
