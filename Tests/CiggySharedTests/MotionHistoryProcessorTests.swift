import XCTest
@testable import CiggyShared

final class MotionHistoryProcessorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testInvalidQueryDatesReturnWithoutCallingProvider() {
        let invalidDates = [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                            Date(timeIntervalSince1970: -1e300), Date(timeIntervalSince1970: 1e300)]
        var queryCount = 0
        for invalid in invalidDates {
            for (lower, upper) in [(invalid, start), (start, invalid), (invalid, invalid)] {
                let result = MotionHistoryProcessor.process(
                    from: lower, to: upper, analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
                    query: { _, _ in queryCount += 1; return nil }
                )
                XCTAssertTrue(MotionHistoryProcessor.isSupportedDate(result.processedThrough))
                XCTAssertTrue(result.pendingRanges.isEmpty)
            }
        }
        XCTAssertEqual(queryCount, 0)
    }

    func testCorruptPendingRangesAreRejectedWithoutCallingProvider() {
        let invalid = Date(timeIntervalSince1970: 1e300)
        var queryCount = 0
        let result = MotionHistoryProcessor.process(
            from: start, to: start, analyzer: .init(),
            pendingRanges: [.init(start: start, end: invalid), .init(start: invalid, end: invalid),
                            .init(start: Date(timeIntervalSince1970: -.infinity), end: start)], sensitivity: 0.5,
            query: { _, _ in queryCount += 1; return nil }
        )
        XCTAssertEqual(queryCount, 0)
        XCTAssertTrue(result.pendingRanges.isEmpty)
    }

    func testOneHundredAdjacentMinuteGapsCoalesceBeforeRetryIntoBoundedBatches() {
        let gaps = (0..<100).map { minute in
            MotionHistoryRange(start: start.addingTimeInterval(Double(minute * 60)),
                               end: start.addingTimeInterval(Double((minute + 1) * 60)))
        }
        let cursor = start.addingTimeInterval(100 * 60)
        var queryCount = 0
        let result = MotionHistoryProcessor.process(
            from: cursor, to: cursor, analyzer: .init(), pendingRanges: gaps, sensitivity: 0.5,
            query: { _, _ in queryCount += 1; return nil }
        )
        XCTAssertEqual(queryCount, 4)
        XCTAssertEqual(result.pendingRanges.count, 4)
        XCTAssertEqual(result.pendingRanges.first?.start, start)
        XCTAssertEqual(result.pendingRanges.last?.end, cursor)
        XCTAssertTrue(result.pendingRanges.allSatisfy { $0.end.timeIntervalSince($0.start) <= 1_800 })
        for pair in zip(result.pendingRanges, result.pendingRanges.dropFirst()) {
            XCTAssertEqual(pair.0.end, pair.1.start)
        }
    }

    func testMissingEarlierQueryIsRetainedWithoutBlockingLaterSamples() throws {
        let end = start.addingTimeInterval(3_600)
        let result = MotionHistoryProcessor.process(
            from: start, to: end, analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
            query: { lower, upper in
                if lower == self.start { return nil }
                return AnySequence([.init(timestamp: upper, x: 0, y: 0, z: 1)])
            }
        )
        XCTAssertEqual(result.processedThrough, end)
        XCTAssertEqual(result.latestSampleAt, end)
        XCTAssertEqual(result.pendingRanges, [.init(start: start, end: start.addingTimeInterval(1_800))])
        // Saving/relaunching retains the exact missing interval for reconciliation.
        let data = try JSONEncoder().encode(result.pendingRanges)
        XCTAssertEqual(try JSONDecoder().decode([MotionHistoryRange].self, from: data), result.pendingRanges)
    }

    func testMissingIntervalsRetryWithContextAndResolveOnlyAfterAvailable() {
        let missing = MotionHistoryRange(start: start, end: start.addingTimeInterval(1_800))
        let cursor = start.addingTimeInterval(3_600)
        var queried: [MotionHistoryRange] = []
        let result = MotionHistoryProcessor.process(
            from: cursor, to: cursor, analyzer: .init(), pendingRanges: [missing], sensitivity: 0.5,
            query: { lower, upper in
                queried.append(.init(start: lower, end: upper))
                return AnySequence([.init(timestamp: upper, x: 0, y: 0, z: 1)])
            }
        )
        XCTAssertEqual(queried.first?.start, start.addingTimeInterval(-480))
        XCTAssertEqual(queried.last?.end, missing.end.addingTimeInterval(480))
        XCTAssertTrue(result.pendingRanges.isEmpty)
        XCTAssertEqual(result.processedThrough, cursor)
    }

    func testEmptyCompletedQueryDiffersFromUnavailableQuery() {
        let end = start.addingTimeInterval(1_800)
        let empty = MotionHistoryProcessor.process(
            from: start, to: end, analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
            query: { _, _ in AnySequence([]) }
        )
        let unavailable = MotionHistoryProcessor.process(
            from: start, to: end, analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
            query: { _, _ in nil }
        )
        XCTAssertTrue(empty.pendingRanges.isEmpty)
        XCTAssertNil(empty.latestSampleAt)
        XCTAssertEqual(unavailable.pendingRanges.count, 1)
        XCTAssertNil(unavailable.latestSampleAt)
    }

    func testInterruptedStreamCheckpointsOnlyConsumedSamples() {
        let samples = (0..<2_000).map {
            RecordedAccelerationSample(timestamp: start.addingTimeInterval(Double($0)), x: 0, y: 0, z: 1)
        }
        var checks = 0
        let result = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(2_000), analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
            query: { _, _ in AnySequence(samples) },
            shouldContinue: { checks += 1; return checks < 2 }
        )
        XCTAssertEqual(result.processedThrough, samples[510].timestamp)
        XCTAssertEqual(result.latestSampleAt, samples[510].timestamp)
        XCTAssertTrue(result.pendingRanges.isEmpty)
    }

    func testExpiredMissingRangesAreReportedAndDoNotCauseUnboundedRetries() {
        let end = start.addingTimeInterval(4 * 86_400)
        var queryCount = 0
        let result = MotionHistoryProcessor.process(
            from: end, to: end, analyzer: .init(),
            pendingRanges: [.init(start: start, end: start.addingTimeInterval(1_800))], sensitivity: 0.5,
            query: { _, _ in queryCount += 1; return nil }
        )
        XCTAssertEqual(queryCount, 0)
        XCTAssertTrue(result.pendingRanges.isEmpty)
        XCTAssertEqual(result.expiredRangeCount, 1)
    }

    func testPartiallyExpiredMissingRangeStillReportsLostCoverage() {
        let end = start.addingTimeInterval(3 * 86_400 + 900)
        var queried: [MotionHistoryRange] = []
        let result = MotionHistoryProcessor.process(
            from: end, to: end, analyzer: .init(),
            pendingRanges: [.init(start: start, end: start.addingTimeInterval(1_800))], sensitivity: 0.5,
            query: { lower, upper in
                queried.append(.init(start: lower, end: upper))
                return AnySequence([])
            }
        )
        XCTAssertEqual(queried.first?.start, start.addingTimeInterval(900))
        XCTAssertTrue(result.pendingRanges.isEmpty, "The still-retained suffix was reconciled")
        XCTAssertEqual(result.expiredRangeCount, 1, "The missing prefix is permanently lost even though the suffix recovered")
    }

    func testRecentReplayContinuesCheckpointWithoutRecountingLongPattern() throws {
        // The initial dense puffs counted once. Sparse puffs still connect to
        // that cigarette, then dense puffs resume after the replay boundary.
        let offsets = [0.0, 20, 40, 60, 80, 220, 360, 500, 640, 660, 680, 700]
        let stream = offsets.flatMap { Array(recordedSession(offset: $0).prefix(1_000)) }
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let checkpoint = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(640), analyzer: .init(), pendingRanges: [],
            sensitivity: 0.5, query: query
        )
        XCTAssertEqual(checkpoint.candidates.count, 1)
        let savedAnalyzer = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(checkpoint.analyzer))
        var queried: [MotionHistoryRange] = []
        let replay = MotionHistoryProcessor.processRecent(
            from: checkpoint.processedThrough, to: start.addingTimeInterval(800), analyzer: savedAnalyzer, sensitivity: 0.5,
            query: { lower, upper in
                queried.append(.init(start: lower, end: upper))
                return query(lower, upper)
            }
        )
        XCTAssertTrue(replay.candidates.isEmpty, "A replay starting mid-pattern cannot create a second cigarette")
        XCTAssertEqual(queried.first?.start, checkpoint.processedThrough)
        XCTAssertTrue(replay.isComplete)
    }

    func testRecentCheckpointPreservesPartialPatternAcrossCursor() {
        let stream = recordedSession(offset: 600)
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let checkpoint = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(660), analyzer: .init(), pendingRanges: [], sensitivity: 0.5, query: query
        )
        XCTAssertTrue(checkpoint.candidates.isEmpty)
        let recent = MotionHistoryProcessor.processRecent(
            from: checkpoint.processedThrough, to: start.addingTimeInterval(720), analyzer: checkpoint.analyzer,
            sensitivity: 0.5, query: query
        )
        let chronological = MotionHistoryProcessor.process(
            from: checkpoint.processedThrough, to: start.addingTimeInterval(720), analyzer: checkpoint.analyzer,
            pendingRanges: [], sensitivity: 0.5, query: query
        )
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertEqual(recent.candidates, chronological.candidates, "The priority pass must not mutate the saved chronological analyzer")
        XCTAssertEqual(checkpoint.processedThrough, start.addingTimeInterval(660))
    }

    func testRecentCheckpointCountsFirstNewPatternWithoutPriorHistory() {
        let stream = recordedSession(offset: 10)
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: start.addingTimeInterval(120), analyzer: .init(), sensitivity: 0.5,
            query: { lower, upper in AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper }) }
        )
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertTrue(recent.isComplete)
    }

    func testRecentCheckpointAllowsNewPatternAfterCountedSessionBreak() {
        let stream = recordedSession(offset: 0) + recordedSession(offset: 650)
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let checkpoint = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(640), analyzer: .init(), pendingRanges: [], sensitivity: 0.5, query: query
        )
        XCTAssertEqual(checkpoint.candidates.count, 1)
        let recent = MotionHistoryProcessor.processRecent(
            from: checkpoint.processedThrough, to: start.addingTimeInterval(800), analyzer: checkpoint.analyzer,
            sensitivity: 0.5, query: query
        )
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertNotEqual(recent.candidates.first?.id, checkpoint.candidates.first?.id)
    }

    func testOldCheckpointStillPrioritizesRecentPatternBeforeBacklog() {
        let end = start.addingTimeInterval(2 * 86_400)
        let stream = recordedSession(offset: 2 * 86_400 - 200)
        var queried: [MotionHistoryRange] = []
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: end, analyzer: .init(), sensitivity: 0.5,
            query: { lower, upper in
                queried.append(.init(start: lower, end: upper))
                return AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
            }
        )
        XCTAssertEqual(queried.first?.start, end.addingTimeInterval(-53 * 60))
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertTrue(recent.isComplete)
    }

    func testRecentPassQueriesBoundedRecentHistoryBeforeDaysOfBacklog() {
        let end = start.addingTimeInterval(2 * 86_400)
        var queried: [MotionHistoryRange] = []
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: end, sensitivity: 0.5,
            query: { lower, upper in
                queried.append(.init(start: lower, end: upper))
                return AnySequence([])
            }
        )
        XCTAssertEqual(recent.requestedFrom, end.addingTimeInterval(-45 * 60))
        XCTAssertEqual(queried.first?.start, end.addingTimeInterval(-53 * 60))
        XCTAssertEqual(queried.last?.end, end)
        XCTAssertEqual(queried.count, 4)
        XCTAssertTrue(queried.allSatisfy { $0.end.timeIntervalSince($0.start) <= 15 * 60 })
        XCTAssertTrue(recent.isComplete)
    }

    func testRecentPassReconstructsSessionAcrossWindowBoundaryAndReplaysStableID() throws {
        let end = start.addingTimeInterval(3_600)
        // The first three complete cycles precede the recent-window boundary;
        // looking at only the recent window would miss this cigarette.
        let stream = recordedSession(offset: 850)
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let first = MotionHistoryProcessor.processRecent(from: start, to: end, sensitivity: 0.5, query: query)
        let replay = MotionHistoryProcessor.processRecent(from: start, to: end, sensitivity: 0.5, query: query)
        let movedWindow = MotionHistoryProcessor.processRecent(
            from: start, to: end.addingTimeInterval(60), sensitivity: 0.5, query: query
        )
        let candidate = try XCTUnwrap(first.candidates.first)
        XCTAssertEqual(first.candidates.count, 1)
        XCTAssertLessThan(try XCTUnwrap(candidate.motionSessionStartedAt), first.requestedFrom)
        XCTAssertGreaterThan(candidate.gestureAt, first.requestedFrom)
        XCTAssertEqual(first.candidates, replay.candidates)
        // Once the full session is outside a sliding window it is excluded, not
        // moved to a new time or synthesized as a new cigarette.
        XCTAssertTrue(movedWindow.candidates.isEmpty)
        XCTAssertTrue(first.isComplete)
    }

    func testRecentPassDoesNotDiscardOlderChronologicalEvents() {
        let end = start.addingTimeInterval(3_600)
        let stream = recordedSession(offset: 100) + recordedSession(offset: 1_100)
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let recent = MotionHistoryProcessor.processRecent(from: start, to: end, sensitivity: 0.5, query: query)
        var chronologicalQueries: [MotionHistoryRange] = []
        let chronological = MotionHistoryProcessor.process(
            from: start, to: end, analyzer: .init(), pendingRanges: [], sensitivity: 0.5,
            query: { lower, upper in
                chronologicalQueries.append(.init(start: lower, end: upper))
                return query(lower, upper)
            }
        )
        XCTAssertEqual(recent.candidates.count, 1)
        XCTAssertEqual(chronologicalQueries.first?.start, start)
        XCTAssertEqual(chronological.candidates.count, 2)
        XCTAssertEqual(recent.candidates.first?.id, chronological.candidates.last?.id)
    }

    func testRecentPassFiltersCandidatesFromPrecedingContext() {
        let end = start.addingTimeInterval(3_600)
        let stream = recordedSession(offset: 450)
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: end, sensitivity: 0.5,
            query: { lower, upper in AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper }) }
        )
        XCTAssertTrue(recent.candidates.isEmpty)
        XCTAssertTrue(recent.isComplete)
    }

    func testUnavailableRecentHistoryIsNotReportedAsCompleteZeroActivity() {
        let end = start.addingTimeInterval(3_600)
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: end, sensitivity: 0.5, query: { _, _ in nil }
        )
        XCTAssertFalse(recent.isComplete)
        XCTAssertFalse(recent.pendingRanges.isEmpty)
        XCTAssertNil(recent.latestSampleAt)
        XCTAssertEqual(recent.processedThrough, end)
    }

    func testRecentPassHonorsRuntimeBudgetWithoutSourceQueryOrCompleteClaim() {
        var queryCount = 0
        let recent = MotionHistoryProcessor.processRecent(
            from: start, to: start.addingTimeInterval(3_600), sensitivity: 0.5,
            query: { _, _ in queryCount += 1; return AnySequence([]) },
            shouldContinue: { false }
        )
        XCTAssertEqual(queryCount, 0)
        XCTAssertFalse(recent.isComplete)
        XCTAssertTrue(recent.candidates.isEmpty)
    }

    func testRecentPassRejectsInvalidBoundsWithoutQueryingSource() {
        var queryCount = 0
        for (lower, upper) in [(Date(timeIntervalSince1970: .nan), start),
                               (start, Date(timeIntervalSince1970: .infinity)),
                               (start.addingTimeInterval(1), start)] {
            let recent = MotionHistoryProcessor.processRecent(
                from: lower, to: upper, sensitivity: 0.5,
                query: { _, _ in queryCount += 1; return AnySequence([]) }
            )
            XCTAssertFalse(recent.isComplete)
            XCTAssertTrue(MotionHistoryProcessor.isSupportedDate(recent.processedThrough))
        }
        XCTAssertEqual(queryCount, 0)
    }

    func testCigaretteCrossingEightMinuteBatchBoundaryCountsOnceAndNextPatternCounts() throws {
        let stream = recordedSession(offset: 420) + recordedSession(offset: 675)
        let query: (Date, Date) -> AnySequence<RecordedAccelerationSample>? = { lower, upper in
            AnySequence(stream.filter { $0.timestamp >= lower && $0.timestamp <= upper })
        }
        let first = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(480), analyzer: .init(), pendingRanges: [],
            sensitivity: 0.5, queryChunkDuration: 480, query: query
        )
        XCTAssertTrue(first.candidates.isEmpty, "The first cigarette is still incomplete at the batch boundary")
        let checkpoint = try JSONDecoder().decode(RecordedMotionAnalyzer.self, from: JSONEncoder().encode(first.analyzer))
        let next = MotionHistoryProcessor.process(
            from: first.processedThrough, to: start.addingTimeInterval(800), analyzer: checkpoint,
            pendingRanges: [], sensitivity: 0.5, queryChunkDuration: 480, query: query
        )
        XCTAssertEqual(next.candidates.count, 2)
        let crossing = try XCTUnwrap(next.candidates.first)
        XCTAssertLessThan(try XCTUnwrap(crossing.motionSessionStartedAt), start.addingTimeInterval(480))
        XCTAssertGreaterThan(crossing.gestureAt, start.addingTimeInterval(480))
        let uninterrupted = MotionHistoryProcessor.process(
            from: start, to: start.addingTimeInterval(800), analyzer: .init(), pendingRanges: [],
            sensitivity: 0.5, queryChunkDuration: 480, query: query
        )
        XCTAssertEqual(next.candidates, uninterrupted.candidates)
    }

    private func recordedSession(offset: Double) -> [RecordedAccelerationSample] {
        (0..<5_000).map { index in
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
