import Foundation
import XCTest
@testable import MyBody

/// Tests that ChartDataPoint carries the source record's UUID,
/// enabling the chart to navigate to the correct report detail on tap.
final class ChartDataPointTests: XCTestCase {

    func test_chartDataPoint_contains_recordID() {
        let recordID = UUID()
        let date = Date()
        let value = 70.5

        let point = ChartDataPoint(date: date, value: value, recordID: recordID)

        XCTAssertEqual(point.recordID, recordID)
        XCTAssertEqual(point.date, date)
        XCTAssertEqual(point.value, value)
    }

    func test_chartDataPoint_id_is_unique() {
        let point1 = ChartDataPoint(date: Date(), value: 1.0, recordID: UUID())
        let point2 = ChartDataPoint(date: Date(), value: 2.0, recordID: UUID())

        XCTAssertNotEqual(point1.id, point2.id)
    }
}
