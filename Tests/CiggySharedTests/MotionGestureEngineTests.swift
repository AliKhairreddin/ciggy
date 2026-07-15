import XCTest
@testable import CiggyShared

final class MotionGestureEngineTests: XCTestCase {
	private let start = Date(timeIntervalSince1970: 1_700_000_000)

	func testDefaultEngineEmitsOneGestureForOneRaise() {
		var engine = MotionGestureEngine()

		XCTAssertNotNil(engine.record(pitch: 1, roll: 1, at: start))
		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start.addingTimeInterval(1)))
	}

	func testHeldPoseCountsAsOnePeak() {
		var engine = MotionGestureEngine(minimumPeaks: 2, minimumPeakSeparation: 0)

		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start))
		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start.addingTimeInterval(0.04)))
		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start.addingTimeInterval(1)))
	}

	func testDistinctThresholdEdgesProduceGesture() {
		var engine = MotionGestureEngine(minimumPeaks: 2, minimumPeakSeparation: 0.5)

		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start))
		XCTAssertNil(engine.record(pitch: 0, roll: 0, at: start.addingTimeInterval(0.2)))
		let gestureAt = engine.record(pitch: 1, roll: 1, at: start.addingTimeInterval(0.8))

		XCTAssertEqual(gestureAt, start.addingTimeInterval(0.8))
	}

	func testCooldownSuppressesRepeatedGesture() {
		var engine = MotionGestureEngine(
			minimumPeaks: 1,
			minimumPeakSeparation: 0,
			gestureCooldown: 8
		)
		XCTAssertNotNil(engine.record(pitch: 1, roll: 1, at: start))
		XCTAssertNil(engine.record(pitch: 0, roll: 0, at: start.addingTimeInterval(1)))
		XCTAssertNil(engine.record(pitch: 1, roll: 1, at: start.addingTimeInterval(2)))
	}
}
