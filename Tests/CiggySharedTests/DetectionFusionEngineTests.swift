import XCTest
@testable import CiggyShared

final class DetectionFusionEngineTests: XCTestCase {
	private let start = Date(timeIntervalSince1970: 1_700_000_000)

	func testSingleGestureDoesNotCreateCandidate() {
		var engine = makeEngine(minimumGestures: 4)

		XCTAssertNil(engine.recordGesture(at: start))
		XCTAssertTrue(engine.hasActiveMotionSession)
		XCTAssertEqual(engine.observedGestureCount, 1)
	}

	func testRepeatedMotionCreatesCandidateWithoutHeartRate() throws {
		var engine = makeEngine(minimumGestures: 4)

		XCTAssertNil(engine.recordGesture(at: start))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(20)))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(40)))
		let candidate = try XCTUnwrap(engine.recordGesture(at: start.addingTimeInterval(60)))

		XCTAssertEqual(candidate.motionSessionStartedAt, start)
		XCTAssertEqual(candidate.motionGestureCount, 4)
		XCTAssertNil(candidate.baselineHeartRate)
		XCTAssertNil(candidate.peakHeartRate)
		XCTAssertFalse(engine.hasActiveMotionSession)
	}

	func testHeartRateIsAttachedAsOptionalContext() throws {
		var engine = makeEngine(minimumGestures: 3)
		engine.recordHeartRate(70, at: start.addingTimeInterval(-20))
		engine.recordHeartRate(72, at: start.addingTimeInterval(-10))
		XCTAssertNil(engine.recordGesture(at: start))
		engine.recordHeartRate(78, at: start.addingTimeInterval(10))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(20)))
		engine.recordHeartRate(84, at: start.addingTimeInterval(30))
		let candidate = try XCTUnwrap(engine.recordGesture(at: start.addingTimeInterval(40)))

		XCTAssertEqual(try XCTUnwrap(candidate.baselineHeartRate), 71, accuracy: 0.001)
		XCTAssertEqual(try XCTUnwrap(candidate.peakHeartRate), 84, accuracy: 0.001)
		XCTAssertEqual(try XCTUnwrap(candidate.heartRateIncrease), 13, accuracy: 0.001)
	}

	func testGesturesThatAreTooCloseAreIgnored() {
		var engine = makeEngine(minimumGestures: 3, minimumSeparation: 6)

		XCTAssertNil(engine.recordGesture(at: start))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(2)))
		XCTAssertEqual(engine.observedGestureCount, 1)
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(10)))
		XCTAssertEqual(engine.observedGestureCount, 2)
	}

	func testLongGapStartsANewMotionSession() {
		var engine = makeEngine(minimumGestures: 3, maximumSeparation: 60)

		XCTAssertNil(engine.recordGesture(at: start))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(20)))
		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(100)))

		XCTAssertEqual(engine.observedGestureCount, 1)
	}

	func testCooldownSuppressesASecondCandidate() {
		var engine = makeEngine(minimumGestures: 2, cooldown: 120)
		XCTAssertNil(engine.recordGesture(at: start))
		XCTAssertNotNil(engine.recordGesture(at: start.addingTimeInterval(20)))

		XCTAssertNil(engine.recordGesture(at: start.addingTimeInterval(40)))
		XCTAssertFalse(engine.hasActiveMotionSession)
	}

	func testSensitivityMapsToMotionCount() {
		var engine = makeEngine()
		engine.updateSensitivity(0)
		XCTAssertEqual(engine.configuration.minimumGestureCount, 7)
		engine.updateSensitivity(0.5)
		XCTAssertEqual(engine.configuration.minimumGestureCount, 5)
		engine.updateSensitivity(1)
		XCTAssertEqual(engine.configuration.minimumGestureCount, 4)
	}

	func testConfirmationCreatesStableAutomaticEvent() {
		let candidate = DetectionCandidate(
			gestureAt: start,
			detectedAt: start.addingTimeInterval(3),
			motionSessionStartedAt: start.addingTimeInterval(-60),
			motionGestureCount: 5,
			baselineHeartRate: 70,
			peakHeartRate: 84
		)

		let event = candidate.confirmedEvent()

		XCTAssertEqual(event.id, candidate.id)
		XCTAssertEqual(event.timestamp, candidate.gestureAt)
		XCTAssertEqual(event.source, .automatic)
		XCTAssertEqual(event.heartRate, 84)
	}

	private func makeEngine(
		minimumGestures: Int = 5,
		minimumSeparation: TimeInterval = 6,
		maximumSeparation: TimeInterval = 150,
		cooldown: TimeInterval = 480
	) -> DetectionFusionEngine {
		DetectionFusionEngine(
			configuration: .init(
				minimumGestureCount: minimumGestures,
				sessionWindowSeconds: 480,
				minimumGestureSeparationSeconds: minimumSeparation,
				maximumGestureSeparationSeconds: maximumSeparation,
				detectionCooldownSeconds: cooldown,
				heartRateContextSeconds: 60
			)
		)
	}
}
