import XCTest
@testable import CiggyShared

final class DetectionFusionEngineTests: XCTestCase {
	private let start = Date(timeIntervalSince1970: 1_700_000_000)

	func testGestureWaitsForPostGestureSamples() {
		var engine = makeEngine()
		_ = engine.recordHeartRate(70, at: start)
		_ = engine.recordHeartRate(72, at: start.addingTimeInterval(1))

		engine.recordGesture(at: start.addingTimeInterval(2))

		XCTAssertTrue(engine.hasPendingGesture)
		XCTAssertNil(engine.recordHeartRate(79, at: start.addingTimeInterval(3)))
		XCTAssertTrue(engine.hasPendingGesture)
	}

	func testCandidateEmitsAfterEnoughPostGestureEvidence() throws {
		var engine = makeEngine()
		_ = engine.recordHeartRate(70, at: start)
		_ = engine.recordHeartRate(70, at: start.addingTimeInterval(1))
		engine.recordGesture(at: start.addingTimeInterval(2))

		XCTAssertNil(engine.recordHeartRate(78, at: start.addingTimeInterval(3)))
		let candidate = try XCTUnwrap(
			engine.recordHeartRate(82, at: start.addingTimeInterval(4))
		)

		XCTAssertEqual(candidate.gestureAt, start.addingTimeInterval(2))
		XCTAssertEqual(candidate.baselineHeartRate, 70, accuracy: 0.001)
		XCTAssertEqual(candidate.peakHeartRate, 82, accuracy: 0.001)
		XCTAssertFalse(engine.hasPendingGesture)
	}

	func testDelayedBaselineSampleIsReconciledByTimestamp() throws {
		var engine = makeEngine()
		engine.recordGesture(at: start.addingTimeInterval(2))
		XCTAssertTrue(engine.hasPendingGesture)

		_ = engine.recordHeartRate(70, at: start.addingTimeInterval(1))
		XCTAssertNil(engine.recordHeartRate(80, at: start.addingTimeInterval(3)))
		let candidate = try XCTUnwrap(
			engine.recordHeartRate(82, at: start.addingTimeInterval(4))
		)

		XCTAssertEqual(candidate.baselineHeartRate, 70, accuracy: 0.001)
		XCTAssertEqual(candidate.peakHeartRate, 82, accuracy: 0.001)
	}

	func testExpiredGestureDoesNotEmitCandidate() {
		var engine = makeEngine(fusionWindow: 10)
		_ = engine.recordHeartRate(70, at: start)
		engine.recordGesture(at: start.addingTimeInterval(1))

		XCTAssertNil(engine.recordHeartRate(100, at: start.addingTimeInterval(12)))
		XCTAssertFalse(engine.hasPendingGesture)
	}

	func testCooldownSuppressesAnotherGesture() {
		var engine = makeEngine(cooldown: 60)
		_ = engine.recordHeartRate(70, at: start)
		engine.recordGesture(at: start.addingTimeInterval(1))
		XCTAssertNil(engine.recordHeartRate(81, at: start.addingTimeInterval(2)))
		XCTAssertNotNil(engine.recordHeartRate(82, at: start.addingTimeInterval(3)))

		_ = engine.recordHeartRate(70, at: start.addingTimeInterval(10))
		engine.recordGesture(at: start.addingTimeInterval(11))
		XCTAssertFalse(engine.hasPendingGesture)
	}

	func testSensitivityMapsToExpectedSpikeThresholds() {
		var engine = makeEngine()
		engine.updateSensitivity(0)
		XCTAssertEqual(engine.configuration.heartRateSpikeBPM, 16)
		engine.updateSensitivity(1)
		XCTAssertEqual(engine.configuration.heartRateSpikeBPM, 6)
	}

	func testConfirmationCreatesStableAutomaticEvent() {
		let candidate = DetectionCandidate(
			gestureAt: start,
			detectedAt: start.addingTimeInterval(3),
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
		fusionWindow: TimeInterval = 20,
		cooldown: TimeInterval = 480
	) -> DetectionFusionEngine {
		DetectionFusionEngine(
			configuration: .init(
				heartRateSpikeBPM: 10,
				fusionWindowSeconds: fusionWindow,
				detectionCooldownSeconds: cooldown,
				minimumPostGestureSamples: 2
			)
		)
	}
}
