import Foundation
import XCTest
@testable import CiggyShared

final class HeartRateReadingTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	func testRecentReadingExpiresWithoutAnotherSample() {
		let reading = HeartRateReading(timestamp: now, beatsPerMinute: 78)
		XCTAssertEqual(reading.currentValue(at: now), 78)
		XCTAssertEqual(reading.currentValue(at: now.addingTimeInterval(120)), 78)
		XCTAssertNil(reading.currentValue(at: now.addingTimeInterval(121)))
	}

	func testFutureReadingsAreNotCurrentContext() {
		let reading = HeartRateReading(timestamp: now.addingTimeInterval(1), beatsPerMinute: 78)
		XCTAssertNil(reading.currentValue(at: now))
	}

	func testInvalidMeasurementsAndTimesAreOmitted() {
		for bpm in [Double.nan, .infinity, -.infinity, 0, -1, 301] {
			XCTAssertNil(HeartRateReading(timestamp: now, beatsPerMinute: bpm).currentValue(at: now))
		}
		let reading = HeartRateReading(timestamp: now, beatsPerMinute: 78)
		XCTAssertNil(reading.currentValue(at: Date(timeIntervalSince1970: .nan)))
		XCTAssertNil(reading.currentValue(at: now, maximumAge: .infinity))
		XCTAssertNil(reading.currentValue(at: now, maximumAge: -1))
		XCTAssertNil(HeartRateReading(timestamp: Date(timeIntervalSince1970: .nan), beatsPerMinute: 78).currentValue(at: now))
	}
}
