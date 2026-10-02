import XCTest
@testable import CiggyShared

final class RecordedMotionAnalyzerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testRepeatedRecordedCyclesCreateCandidate() throws {
        var analyzer = RecordedMotionAnalyzer()
        let candidates = samples(cycles: 5).compactMap { analyzer.record($0) }
        let detected = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(detected.motionGestureCount, 5)
        XCTAssertNil(detected.peakHeartRate)
        XCTAssertGreaterThan(detected.gestureAt.timeIntervalSince(start), 85)
        XCTAssertLessThan(detected.gestureAt.timeIntervalSince(start), 90)
    }

    func testStaticMotionDoesNotCreateCandidate() {
        var analyzer = RecordedMotionAnalyzer(sensitivity: 1)
        for index in 0..<3_000 {
            XCTAssertNil(analyzer.record(.init(timestamp: start.addingTimeInterval(Double(index) * 0.02), x: 0, y: 0, z: -1)))
        }
    }

    func testCheckpointRestoresPartialSessionAndProducesSameCandidateID() throws {
        let stream = samples(cycles: 5)
        var uninterrupted = RecordedMotionAnalyzer()
        let expected = stream.compactMap { uninterrupted.record($0) }
        var resumed = RecordedMotionAnalyzer()
        let split = stream.count / 2
        var actual = stream.prefix(split).compactMap { resumed.record($0) }
        resumed = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(resumed))
        actual += stream.dropFirst(split).compactMap { resumed.record($0) }
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 1)
    }

    func testReplayProducesStableIDsAndCooldownSurvivesCheckpoint() throws {
        let stream = samples(cycles: 5)
        var first = RecordedMotionAnalyzer()
        let candidate = try XCTUnwrap(stream.compactMap { first.record($0) }.first)
        var replay = RecordedMotionAnalyzer()
        XCTAssertEqual(stream.compactMap { replay.record($0) }.first?.id, candidate.id)
        first = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(first))
        for sample in samples(cycles: 5, offset: 100) { XCTAssertNil(first.record(sample)) }
    }

    func testMalformedAndOutOfOrderSamplesAreIgnored() {
        var analyzer = RecordedMotionAnalyzer()
        XCTAssertNil(analyzer.record(.init(timestamp: start, x: .nan, y: 0, z: 0)))
        XCTAssertNil(analyzer.record(.init(timestamp: start, x: 0, y: 0, z: -1)))
        XCTAssertNil(analyzer.record(.init(timestamp: start.addingTimeInterval(-1), x: 1, y: 0, z: 0)))
    }

    private func samples(cycles: Int, offset: Double = 0) -> [RecordedAccelerationSample] {
        (0..<(cycles * 1_000)).map { index in
            let seconds = Double(index) * 0.02
            let local = seconds.truncatingRemainder(dividingBy: 20)
            let angle: Double
            if local < 2 { angle = 0 }
            else if local < 3 { angle = local - 2 }
            else if local < 5 { angle = 1 }
            else if local < 6 { angle = 6 - local }
            else { angle = 0 }
            return .init(timestamp: start.addingTimeInterval(offset + seconds), x: sin(angle), y: 0, z: -cos(angle))
        }
    }
}
