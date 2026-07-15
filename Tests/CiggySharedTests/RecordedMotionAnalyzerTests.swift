import XCTest
@testable import CiggyShared

final class RecordedMotionAnalyzerTests: XCTestCase {
	private let start = Date(timeIntervalSince1970: 1_700_000_000)

	func testRepeatedRecordedRaisesCreateCandidate() throws {
		var analyzer = RecordedMotionAnalyzer(sensitivity: 0.5)
		var candidate: DetectionCandidate?

		for gestureIndex in 0..<5 {
			let gestureStart = start.addingTimeInterval(Double(gestureIndex) * 20)
			feedNeutral(into: &analyzer, startingAt: gestureStart)
			candidate = feedRaised(into: &analyzer, startingAt: gestureStart.addingTimeInterval(1)) ?? candidate
		}

		let detected = try XCTUnwrap(candidate)
		XCTAssertEqual(detected.motionGestureCount, 5)
		XCTAssertEqual(detected.gestureAt.timeIntervalSince(start), 81.1, accuracy: 0.11)
	}

	func testStaticNeutralRecordedMotionDoesNotCreateCandidate() {
		var analyzer = RecordedMotionAnalyzer(sensitivity: 1)
		var candidate: DetectionCandidate?

		for index in 0..<600 {
			candidate = analyzer.record(
				.init(
					timestamp: start.addingTimeInterval(Double(index) * 0.1),
					x: 0,
					y: 0,
					z: -1
				)
			) ?? candidate
		}

		XCTAssertNil(candidate)
	}

	private func feedNeutral(
		into analyzer: inout RecordedMotionAnalyzer,
		startingAt timestamp: Date
	) {
		for index in 0..<10 {
			_ = analyzer.record(
				.init(
					timestamp: timestamp.addingTimeInterval(Double(index) * 0.1),
					x: 0,
					y: 0,
					z: -1
				)
			)
		}
	}

	private func feedRaised(
		into analyzer: inout RecordedMotionAnalyzer,
		startingAt timestamp: Date
	) -> DetectionCandidate? {
		var candidate: DetectionCandidate?
		for index in 0..<10 {
			candidate = analyzer.record(
				.init(
					timestamp: timestamp.addingTimeInterval(Double(index) * 0.1),
					x: -0.8,
					y: 0.6,
					z: 0
				)
			) ?? candidate
		}
		return candidate
	}
}
