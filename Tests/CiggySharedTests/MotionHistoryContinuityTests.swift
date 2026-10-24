import XCTest
@testable import CiggyShared

final class MotionHistoryContinuityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var firstEpisode: [Double] {
        [0, 20, 40, 60, 80] + Array(stride(from: 220.0, through: 1_340, by: 140)) + [1_360, 1_380, 1_400]
    }
    private var secondEpisode: [Double] { [2_000, 2_020, 2_040, 2_060, 2_080] }

    func testColdRecentReplayDefersTruncatedEpisodeAndCountsLaterProvenBoundary() {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let complete = process(samples, end: 4_000)
        XCTAssertEqual(complete.candidates.count, 2)
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: date(4_000), analyzer: .init(), sourceStartedAt: start,
            sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertEqual(recent.candidates.map(\.id), Array(complete.candidates.suffix(1).map(\.id)))
        XCTAssertFalse(recent.isComplete, "The truncated first episode must remain pending, not become a second count")
        XCTAssertFalse(recent.pendingRanges.isEmpty)
    }

    func testKnownCaptureStartCountsFirstEpisodeImmediately() {
        let samples = trace(cycles: [0, 20, 40, 60, 80], duration: 120)
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: date(120), sourceStartedAt: start, sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertTrue(recent.isComplete)
    }

    func testUnavailableChunkCannotSplitExistingEpisodeAndRecoveryKeepsStableIDs() throws {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let full = process(samples, end: 4_000)
        let query = provider(samples)
        let missing = MotionHistoryProcessor.process(
            from: start, to: date(4_000), analyzer: .init(), pendingRanges: [], sourceStartedAt: start,
            sensitivity: 0.5, queryChunkDuration: 500,
            query: { lower, upper in lower == self.date(1_000) ? nil : query(lower, upper) }
        )
        XCTAssertEqual(missing.candidates.map(\.id), full.candidates.map(\.id))
        XCTAssertFalse(missing.pendingRanges.isEmpty)
        XCTAssertFalse(missing.replayCheckpoints.isEmpty)
        let saved = try JSONDecoder().decode([MotionHistoryReplayCheckpoint].self,
                                             from: JSONEncoder().encode(missing.replayCheckpoints))
        let repaired = MotionHistoryProcessor.process(
            from: missing.processedThrough, to: date(4_000), analyzer: missing.analyzer,
            pendingRanges: missing.pendingRanges, replayCheckpoints: saved, sourceStartedAt: start,
            sensitivity: 0.5, queryChunkDuration: 500, query: query
        )
        XCTAssertTrue(repaired.pendingRanges.isEmpty)
        XCTAssertTrue(repaired.replayCheckpoints.isEmpty)
        XCTAssertEqual(Set((missing.candidates + repaired.candidates).map(\.id)), Set(full.candidates.map(\.id)))
        XCTAssertFalse(repaired.candidates.contains { $0.gestureAt > self.date(1_300) && $0.gestureAt < self.date(1_500) })
        let next = MotionHistoryProcessor.process(
            from: repaired.processedThrough, to: date(4_000), analyzer: repaired.analyzer,
            pendingRanges: repaired.pendingRanges, replayCheckpoints: repaired.replayCheckpoints,
            sourceStartedAt: start, sensitivity: 0.5, query: query
        )
        XCTAssertTrue(next.candidates.isEmpty)
    }

    func testLegacyGapWithoutCheckpointReplaysFromKnownOriginWithoutExtraCount() {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let full = process(samples, end: 4_000)
        let repaired = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer,
            pendingRanges: [.init(start: date(1_300), end: date(1_500))], sourceStartedAt: start,
            sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertEqual(repaired.candidates.map(\.id), full.candidates.map(\.id))
        XCTAssertTrue(repaired.pendingRanges.isEmpty)
    }

    func testInterruptedReconciliationResumesExactPersistedClassifierAndCursor() throws {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let full = process(samples, end: 4_000)
        let range = MotionHistoryRange(start: date(1_300), end: date(1_500))
        var checks = 0
        let interrupted = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer,
            pendingRanges: [range], sourceStartedAt: start, sensitivity: 0.5, query: provider(samples),
            shouldContinue: { checks += 1; return checks < 4 }
        )
        let saved = try JSONDecoder().decode([MotionHistoryReplayCheckpoint].self,
                                             from: JSONEncoder().encode(interrupted.replayCheckpoints))
        let cursor = try XCTUnwrap(saved.first?.processedThrough)
        XCTAssertGreaterThan(cursor, start)
        XCTAssertLessThan(cursor, date(4_000))
        var firstQuery: Date?
        let query = provider(samples)
        let resumed = MotionHistoryProcessor.process(
            from: interrupted.processedThrough, to: date(4_000), analyzer: interrupted.analyzer,
            pendingRanges: interrupted.pendingRanges, replayCheckpoints: saved, sourceStartedAt: start,
            sensitivity: 0.5, query: { lower, upper in
                if firstQuery == nil { firstQuery = lower }
                return query(lower, upper)
            }
        )
        XCTAssertEqual(firstQuery, cursor)
        XCTAssertTrue(resumed.pendingRanges.isEmpty)
        XCTAssertEqual(Set((interrupted.candidates + resumed.candidates).map(\.id)), Set(full.candidates.map(\.id)))
    }

    func testMissingAndMalformedSamplesCannotProveQuietBoundary() {
        for mode in 0..<3 {
            var analyzer = RecordedMotionAnalyzer(requiresConfirmedBoundary: true)
            for sample in trace(cycles: [], duration: 200) {
                let t = sample.timestamp.timeIntervalSince(start)
                if mode == 0 && t > 80 && t < 100 { continue }
                if mode == 1 && abs(t - 100) < 0.001 {
                    _ = analyzer.record(.init(timestamp: sample.timestamp, x: .nan, y: 0, z: -1))
                } else if mode == 2 && abs(t - 100) < 0.001 {
                    _ = analyzer.record(.init(timestamp: Date(timeIntervalSince1970: .nan), x: 0, y: 0, z: -1))
                } else { _ = analyzer.record(sample) }
            }
            XCTAssertFalse(analyzer.hasConfirmedContinuity, "Mode \(mode) contains unobserved source, not 150s of measured quiet")
        }
    }

    func testQuietBoundaryRequiresMoreThanExactly150Seconds() {
        var analyzer = RecordedMotionAnalyzer(requiresConfirmedBoundary: true)
        for sample in trace(cycles: [], duration: 150) { _ = analyzer.record(sample) }
        XCTAssertFalse(analyzer.hasConfirmedContinuity)
        _ = analyzer.record(.init(timestamp: date(150.1), x: 0, y: 0, z: -1))
        XCTAssertTrue(analyzer.hasConfirmedContinuity)
    }

    func testEmptyQueryDoesNotSupplyQuietProofForColdReplay() {
        let samples = trace(cycles: [3_000, 3_020, 3_040, 3_060, 3_080], duration: 3_120)
            .filter { $0.timestamp >= date(3_000) }
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: date(3_120), sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertTrue(recent.candidates.isEmpty)
        XCTAssertFalse(recent.isComplete)
    }

    func testActualSourceGapRemainsRetryableAndRecoversWhenSamplesArrive() {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let incomplete = samples.filter { $0.timestamp <= date(1_000) || $0.timestamp >= date(1_300) }
        let missing = process(incomplete, end: 4_000)
        XCTAssertFalse(missing.pendingRanges.isEmpty)
        let repaired = MotionHistoryProcessor.process(
            from: missing.processedThrough, to: date(4_000), analyzer: missing.analyzer,
            pendingRanges: missing.pendingRanges, replayCheckpoints: missing.replayCheckpoints, sourceStartedAt: start,
            sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertTrue(repaired.pendingRanges.isEmpty)
        XCTAssertEqual(Set((missing.candidates + repaired.candidates).map(\.id)), Set(process(samples, end: 4_000).candidates.map(\.id)))
    }

    func testEmptyAndClippedRetriesCannotRetireKnownMissingCoverage() {
        let range = MotionHistoryRange(start: start, end: date(500))
        let original = RecordedMotionAnalyzer()
        let checkpoint = MotionHistoryReplayCheckpoint(range: range, origin: start,
            processedThrough: start, analyzer: original, originAnalyzer: original)
        for mode in 0..<3 {
            let samples = trace(cycles: [], duration: 1_000).filter {
                mode == 1 ? $0.timestamp >= date(20) : (mode == 2 && $0.timestamp <= date(980))
            }
            let result = MotionHistoryProcessor.process(
                from: date(1_000), to: date(1_000), analyzer: original, pendingRanges: [range],
                replayCheckpoints: [checkpoint], sourceStartedAt: start, sensitivity: 0.5, query: provider(samples)
            )
            XCTAssertEqual(result.pendingRanges, [range], "Empty/clipped recovery mode \(mode) cannot prove full source coverage")
            XCTAssertEqual(result.replayCheckpoints.first?.processedThrough, start)
            XCTAssertTrue(result.candidates.isEmpty)
        }
    }

    func testAmbiguousLegacyEpisodeDoesNotHideLaterProvenEpisode() {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let full = process(samples, end: 4_000)
        let range = MotionHistoryRange(start: date(1_300), end: date(1_500))
        let cold = RecordedMotionAnalyzer(requiresConfirmedBoundary: true)
        let checkpoint = MotionHistoryReplayCheckpoint(range: range, origin: start, processedThrough: start,
            analyzer: cold, originAnalyzer: cold)
        let retry = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer, pendingRanges: [range],
            replayCheckpoints: [checkpoint], sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertEqual(retry.candidates.map(\.id), Array(full.candidates.suffix(1).map(\.id)))
        XCTAssertEqual(retry.pendingRanges, [range], "The initial ambiguous episode stays explicitly unresolved")
    }

    func testClippedFirstQueryCannotTreatContinuingEpisodeAsNewCapture() {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let complete = process(samples, end: 4_000)
        let clipped = process(samples.filter { $0.timestamp >= date(500) }, end: 4_000)
        XCTAssertEqual(clipped.candidates.map(\.id), Array(complete.candidates.suffix(1).map(\.id)))
        XCTAssertFalse(clipped.pendingRanges.isEmpty)
    }

    func testInterruptedRetryPreservesEarlierCoverageFailureAcrossRelaunch() throws {
        let samples = trace(cycles: firstEpisode + secondEpisode, duration: 4_000)
        let incomplete = samples.filter { $0.timestamp <= date(1_000) || $0.timestamp >= date(1_300) }
        let full = process(samples, end: 4_000)
        let range = MotionHistoryRange(start: date(1_000), end: date(1_300))
        var checks = 0
        let interrupted = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer, pendingRanges: [range],
            sourceStartedAt: start, sensitivity: 0.5, query: provider(incomplete),
            shouldContinue: { checks += 1; return checks < 30 }
        )
        let saved = try JSONDecoder().decode([MotionHistoryReplayCheckpoint].self,
                                             from: JSONEncoder().encode(interrupted.replayCheckpoints))
        XCTAssertEqual(saved.first?.hasUnresolvedCoverage, true)
        XCTAssertGreaterThan(try XCTUnwrap(saved.first?.processedThrough), date(1_300))
        let resumed = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer, pendingRanges: interrupted.pendingRanges,
            replayCheckpoints: saved, sourceStartedAt: start, sensitivity: 0.5, query: provider(incomplete)
        )
        XCTAssertEqual(resumed.pendingRanges, [range])
        XCTAssertEqual(resumed.replayCheckpoints.first?.processedThrough, start)
        let repaired = MotionHistoryProcessor.process(
            from: date(4_000), to: date(4_000), analyzer: full.analyzer, pendingRanges: resumed.pendingRanges,
            replayCheckpoints: resumed.replayCheckpoints, sourceStartedAt: start, sensitivity: 0.5, query: provider(samples)
        )
        XCTAssertTrue(repaired.pendingRanges.isEmpty)
        XCTAssertEqual(Set((interrupted.candidates + resumed.candidates + repaired.candidates).map(\.id)), Set(full.candidates.map(\.id)))
    }

    private func process(_ samples: [RecordedAccelerationSample], end: Double) -> MotionHistoryProcessor.Result {
        MotionHistoryProcessor.process(from: start, to: date(end), analyzer: .init(), pendingRanges: [],
                                       sourceStartedAt: start, sensitivity: 0.5, query: provider(samples))
    }
    private func provider(_ samples: [RecordedAccelerationSample]) -> (Date, Date) -> AnySequence<RecordedAccelerationSample>? {
        { lower, upper in AnySequence(samples.filter { $0.timestamp >= lower && $0.timestamp <= upper }) }
    }
    private func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    private func trace(cycles: [Double], duration: Double) -> [RecordedAccelerationSample] {
        (0...Int(duration * 10)).map { index in
            let t = Double(index) / 10
            let cycle = cycles.last { $0 <= t }
            let local = cycle.map { t - $0 } ?? -1
            let angle: Double
            if local >= 2 && local < 3 { angle = local - 2 }
            else if local >= 3 && local < 5 { angle = 1 }
            else if local >= 5 && local < 6 { angle = 6 - local }
            else { angle = 0 }
            return .init(timestamp: date(t), x: sin(angle), y: 0, z: -cos(angle))
        }
    }
}
