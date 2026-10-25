import XCTest
@testable import CiggyShared

final class RecordedMotionAnalyzerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testRepeatedRecordedCyclesCreateCandidate() throws {
        var analyzer = RecordedMotionAnalyzer()
        let candidates = samples(cycles: 16).compactMap { analyzer.record($0) }
        let detected = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(detected.motionGestureCount, 16)
        XCTAssertNil(detected.peakHeartRate)
        XCTAssertGreaterThan(detected.gestureAt.timeIntervalSince(start), 305)
        XCTAssertLessThan(detected.gestureAt.timeIntervalSince(start), 310)
        XCTAssertGreaterThanOrEqual(detected.gestureAt.timeIntervalSince(try XCTUnwrap(detected.motionSessionStartedAt)), 300)
    }

    func testRepeatedCyclesBelowDurationThresholdDoNotCount() {
        var analyzer = RecordedMotionAnalyzer()
        XCTAssertTrue(samples(cycles: 15).compactMap { analyzer.record($0) }.isEmpty)
    }

    func testStaticMotionDoesNotCreateCandidate() {
        var analyzer = RecordedMotionAnalyzer(sensitivity: 1)
        for index in 0..<3_000 {
            XCTAssertNil(analyzer.record(.init(timestamp: start.addingTimeInterval(Double(index) * 0.02), x: 0, y: 0, z: -1)))
        }
    }

    func testCheckpointRestoresPartialSessionAndProducesSameCandidateID() throws {
        let stream = samples(cycles: 16)
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

    func testReplayProducesStableIDsAndContinuingSessionSurvivesCheckpoint() throws {
        let stream = samples(cycles: 16)
        var first = RecordedMotionAnalyzer()
        let candidate = try XCTUnwrap(stream.compactMap { first.record($0) }.first)
        var replay = RecordedMotionAnalyzer()
        XCTAssertEqual(stream.compactMap { replay.record($0) }.first?.id, candidate.id)
        first = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(first))
        for sample in samples(cycles: 14, offset: 320) { XCTAssertNil(first.record(sample)) }
        let next = samples(cycles: 1, offset: 600).compactMap { first.record($0) }
        XCTAssertEqual(next.count, 1)
        XCTAssertNotEqual(next.first?.id, candidate.id)
    }

    func testSeparateRecordedPatternsEachRequireDurationAcrossCheckpoint() throws {
        var analyzer = RecordedMotionAnalyzer()
        var detected = samples(cycles: 16).compactMap { analyzer.record($0) }
        analyzer = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(analyzer))
        for sample in rest(from: 320, to: 500) { XCTAssertNil(analyzer.record(sample)) }
        detected += samples(cycles: 16, offset: 500).compactMap { analyzer.record($0) }
        XCTAssertEqual(detected.count, 2)
        XCTAssertEqual(Set(detected.map(\.id)).count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(detected.last?.gestureAt).timeIntervalSince(start), 800)
    }

    func testLongRecordedPatternCountsSuccessiveDurationSegments() throws {
        var analyzer = RecordedMotionAnalyzer()
        let candidates = samples(cycles: 47).compactMap { analyzer.record($0) }
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(Set(candidates.map(\.id)).count, 3)
        for pair in zip(candidates, candidates.dropFirst()) {
            XCTAssertEqual(pair.1.motionSessionStartedAt, pair.0.gestureAt)
            XCTAssertGreaterThanOrEqual(pair.1.gestureAt.timeIntervalSince(pair.0.gestureAt), 300)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(pair.1.motionGestureCount), 5)
        }
    }

    func testMalformedAndOutOfOrderSamplesAreIgnored() {
        var analyzer = RecordedMotionAnalyzer()
        XCTAssertNil(analyzer.record(.init(timestamp: start, x: .nan, y: 0, z: 0)))
        XCTAssertNil(analyzer.record(.init(timestamp: start, x: 0, y: 0, z: -1)))
        XCTAssertNil(analyzer.record(.init(timestamp: start.addingTimeInterval(-1), x: 1, y: 0, z: 0)))
    }

    func testMalformedSampleBreaksInterruptedCycleButLaterSessionRecovers() {
        var analyzer = RecordedMotionAnalyzer()
        let stream = samples(cycles: 5)
        var detected: [DetectionCandidate] = []
        for sample in stream {
            let seconds = sample.timestamp.timeIntervalSince(start)
            let input = abs(seconds - 4) < 0.001
                ? RecordedAccelerationSample(timestamp: sample.timestamp, x: .nan, y: 0, z: 0) : sample
            if let candidate = analyzer.record(input) { detected.append(candidate) }
        }
        XCTAssertTrue(detected.isEmpty, "Four intact cycles cannot become a five-cycle session")
        for sample in rest(from: 100, to: 300) { XCTAssertNil(analyzer.record(sample)) }
        let recovered = samples(cycles: 16, offset: 300).compactMap { analyzer.record($0) }
        XCTAssertEqual(recovered.count, 1)
    }

    func testNonFiniteFilterParametersUseWorkingDefaults() {
        var analyzer = RecordedMotionAnalyzer(sampleInterval: .infinity, gravityTimeConstant: .nan)
        XCTAssertEqual(analyzer.sampleInterval, 0.1)
        XCTAssertEqual(analyzer.gravityTimeConstant, 0.25)
        XCTAssertEqual(samples(cycles: 16).compactMap { analyzer.record($0) }.count, 1)
    }

    func testUnknownSourceGapCannotSupplyDurationForNextSegment() throws {
        var analyzer = RecordedMotionAnalyzer()
        XCTAssertEqual(samples(cycles: 16).compactMap { analyzer.record($0) }.count, 1)
        // The unobserved interval must not be treated as smoking or quiet rest.
        XCTAssertTrue(samples(cycles: 16, offset: 400).compactMap { analyzer.record($0) }.isEmpty)
        XCTAssertFalse(analyzer.hasConfirmedContinuity)
        for sample in rest(from: 720, to: 900) { XCTAssertNil(analyzer.record(sample)) }
        XCTAssertTrue(analyzer.hasConfirmedContinuity)
        let recovered = samples(cycles: 16, offset: 900).compactMap { analyzer.record($0) }
        XCTAssertEqual(recovered.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(recovered.first).gestureAt.timeIntervalSince(start), 1_200)
    }

    func testLegacyAnalyzerCheckpointRequiresFreshDurationEvidence() throws {
        var analyzer = RecordedMotionAnalyzer()
        XCTAssertTrue(samples(cycles: 8).compactMap { analyzer.record($0) }.isEmpty)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(analyzer)) as? [String: Any])
        var fusion = try XCTUnwrap(legacy["fusionEngine"] as? [String: Any])
        var configuration = try XCTUnwrap(fusion["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "minimumSmokingDurationSeconds")
        fusion["configuration"] = configuration
        fusion.removeValue(forKey: "durationSegmentStartedAt")
        fusion.removeValue(forKey: "durationModelVersion")
        legacy["fusionEngine"] = fusion
        analyzer = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONSerialization.data(withJSONObject: legacy))
        let candidates = samples(cycles: 16, offset: 160).compactMap { analyzer.record($0) }
        XCTAssertEqual(candidates.count, 1)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertGreaterThan(candidate.gestureAt.timeIntervalSince(start), 465,
                             "An old checkpoint contains no proof for the new five-minute duration rule")
        XCTAssertLessThan(candidate.gestureAt.timeIntervalSince(start), 470)
    }

    private func rest(from lower: Double, to upper: Double) -> [RecordedAccelerationSample] {
        (0..<Int((upper - lower) * 10)).map {
            .init(timestamp: start.addingTimeInterval(lower + Double($0) / 10), x: 0, y: 0, z: -1)
        }
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
