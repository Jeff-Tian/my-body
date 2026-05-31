import XCTest
@testable import MyBody

final class ScanRangeAnchoredTests: XCTestCase {
    func testAnchoredStartDateIsRelativeToProvidedAnchorNotNow() {
        let calendar = Calendar.current
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            ScanRange.last30Days.startDate(anchoredAt: anchor),
            calendar.date(byAdding: .day, value: -30, to: anchor)
        )
        XCTAssertEqual(
            ScanRange.last90Days.startDate(anchoredAt: anchor),
            calendar.date(byAdding: .day, value: -90, to: anchor)
        )
        XCTAssertEqual(
            ScanRange.lastYear.startDate(anchoredAt: anchor),
            calendar.date(byAdding: .year, value: -1, to: anchor)
        )
        XCTAssertNil(ScanRange.all.startDate(anchoredAt: anchor))
    }

    func testAnchoredWindowDoesNotDriftWithDifferentAnchors() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day3 = day1.addingTimeInterval(2 * 24 * 60 * 60)

        let frozen = ScanRange.last90Days.startDate(anchoredAt: day1)
        let recomputedAtResume = ScanRange.last90Days.startDate(anchoredAt: day3)

        // The frozen window must stay anchored to day1, not shift forward to day3.
        XCTAssertNotEqual(frozen, recomputedAtResume)
        XCTAssertEqual(
            frozen,
            Calendar.current.date(byAdding: .day, value: -90, to: day1)
        )
    }
}
