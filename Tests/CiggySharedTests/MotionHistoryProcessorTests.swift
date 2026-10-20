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
}
