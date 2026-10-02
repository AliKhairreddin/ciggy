import XCTest
@testable import CiggyShared

final class MotionGestureEngineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testCompleteRaiseHoldReturnCountsOnce() {
        var engine = MotionGestureEngine()
        let samples = MotionFixtures.cycle(start: start)
        let gestures = samples.compactMap { engine.record($0) }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(engine.phase, .resting)
    }

    func testBothMirroredWristOrientationsCount() {
        for mirror in [-1.0, 1.0] {
            var engine = MotionGestureEngine()
            XCTAssertEqual(MotionFixtures.cycle(start: start, mirror: mirror).compactMap { engine.record($0) }.count, 1)
        }
    }

    func testStaticRaisedWristDoesNotCount() {
        var engine = MotionGestureEngine()
        for index in 0..<900 {
            XCTAssertNil(engine.record(MotionFixtures.sample(start: start, seconds: Double(index) / 30, angle: 1)))
        }
    }

    func testBriefFlickWithoutSteadyHoldDoesNotCount() {
        var engine = MotionGestureEngine()
        let gestures = MotionFixtures.cycle(start: start, hold: 0.1).compactMap { engine.record($0) }
        XCTAssertTrue(gestures.isEmpty)
    }

    func testRaisingWithoutLoweringDoesNotCount() {
        var engine = MotionGestureEngine()
        for sample in MotionFixtures.cycle(start: start).filter({ $0.timestamp < start.addingTimeInterval(3.5) }) {
            XCTAssertNil(engine.record(sample))
        }
    }

    func testSensorGapCannotCompleteAnInterruptedCycle() {
        var engine = MotionGestureEngine()
        for sample in MotionFixtures.cycle(start: start).filter({ $0.timestamp < start.addingTimeInterval(3.5) }) {
            XCTAssertNil(engine.record(sample))
        }
        for index in 0..<90 {
            XCTAssertNil(engine.record(MotionFixtures.sample(start: start, seconds: 10 + Double(index) / 30, angle: 0)))
        }
    }

    func testMovementDuringHoldIsRejected() {
        var engine = MotionGestureEngine()
        let samples = MotionFixtures.cycle(start: start).map { sample in
            let seconds = sample.timestamp.timeIntervalSince(start)
            return seconds >= 2 && seconds <= 4
                ? MotionSample(timestamp: sample.timestamp, gravity: sample.gravity,
                               userAcceleration: .init(x: 0.7, y: 0, z: 0), rotationRate: sample.rotationRate)
                : sample
        }
        XCTAssertTrue(samples.compactMap { engine.record($0) }.isEmpty)
    }

    func testDuplicateAndBackwardSamplesDoNotChangeGestureCount() {
        var engine = MotionGestureEngine()
        var count = 0
        for sample in MotionFixtures.cycle(start: start) {
            if engine.record(sample) != nil { count += 1 }
            XCTAssertNil(engine.record(sample))
            XCTAssertNil(engine.record(MotionFixtures.sample(start: start, seconds: -10, angle: 0)))
        }
        XCTAssertEqual(count, 1)
    }

    func testInvalidSampleCancelsCurrentGesture() {
        var engine = MotionGestureEngine()
        for sample in MotionFixtures.cycle(start: start).prefix(100) { _ = engine.record(sample) }
        XCTAssertNil(engine.record(.init(timestamp: start.addingTimeInterval(3.4),
            gravity: .init(x: .nan, y: 0, z: 0), userAcceleration: .init(x: 0, y: 0, z: 0), rotationRate: nil)))
        XCTAssertEqual(engine.phase, .seekingRest)
    }

    func testAccelerometerOnlySamplesInferRotationWithoutInventingGyroscope() {
        var engine = MotionGestureEngine()
        let samples = MotionFixtures.cycle(start: start).map {
            MotionSample(timestamp: $0.timestamp, gravity: $0.gravity, userAcceleration: $0.userAcceleration,
                         rotationRate: nil, source: .recordedAccelerometer)
        }
        XCTAssertEqual(samples.compactMap { engine.record($0) }.count, 1)
    }
}

enum MotionFixtures {
    static func sample(start: Date, seconds: Double, angle: Double, rate: Double = 0, mirror: Double = 1) -> MotionSample {
        .init(timestamp: start.addingTimeInterval(seconds),
              gravity: .init(x: mirror * sin(angle), y: 0, z: -cos(angle)),
              userAcceleration: .init(x: 0, y: 0, z: 0),
              rotationRate: .init(x: 0, y: mirror * rate, z: 0))
    }
    static func cycle(start: Date, hold: Double = 2, mirror: Double = 1) -> [MotionSample] {
        let duration = 4 + hold
        return (0...Int(duration * 30)).map { index in
            let t = Double(index) / 30
            let angle: Double
            let rate: Double
            if t < 1 { angle = 0; rate = 0 }
            else if t < 2 { angle = t - 1; rate = 1 }
            else if t < 2 + hold { angle = 1; rate = 0 }
            else if t < 3 + hold { angle = 3 + hold - t; rate = -1 }
            else { angle = 0; rate = 0 }
            return sample(start: start, seconds: t, angle: angle, rate: rate, mirror: mirror)
        }
    }
}
