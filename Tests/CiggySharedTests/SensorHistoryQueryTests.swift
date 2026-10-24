import XCTest
@testable import CiggyShared

final class SensorHistoryQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testDelayedAnalysisCutoffCannotProduceOutOfRetentionNativeQuery() throws {
        let end = now.addingTimeInterval(-180)
        let oldReplayStart = end.addingTimeInterval(-SensorHistoryQuery.retention)
        let range = try XCTUnwrap(SensorHistoryQuery.range(from: oldReplayStart,
            to: oldReplayStart.addingTimeInterval(1800), now: now))
        XCTAssertEqual(range.start, now.addingTimeInterval(-SensorHistoryQuery.retention + 5))
        XCTAssertEqual(range.end, oldReplayStart.addingTimeInterval(1800))
    }

    func testExpiredAndInvalidQueriesNeverReachSensor() {
        let expired = now.addingTimeInterval(-SensorHistoryQuery.retention)
        XCTAssertNil(SensorHistoryQuery.range(from: expired.addingTimeInterval(-600), to: expired, now: now))
        XCTAssertNil(SensorHistoryQuery.range(from: now, to: now, now: now))
        XCTAssertNil(SensorHistoryQuery.range(from: now.addingTimeInterval(10), to: now, now: now))
        XCTAssertNil(SensorHistoryQuery.range(from: Date(timeIntervalSince1970: .nan), to: now, now: now))
        XCTAssertNil(SensorHistoryQuery.range(from: now, to: .distantFuture, now: now))
    }

    func testRecentCalibrationWindowIsUnchangedAndOversizedQueriesAreBounded() throws {
        let start = now.addingTimeInterval(-600), end = now.addingTimeInterval(-300)
        XCTAssertEqual(SensorHistoryQuery.range(from: start, to: end, now: now), .init(start: start, end: end))
        let range = try XCTUnwrap(SensorHistoryQuery.range(from: now.addingTimeInterval(-86400),
            to: now.addingTimeInterval(100), now: now))
        XCTAssertEqual(range.end, now)
        XCTAssertEqual(range.end.timeIntervalSince(range.start), 43200)
    }

    func testSavedRepairReplayQueriesStaySafeWithoutChangingClassifier() {
        let end = now.addingTimeInterval(-180)
        let expiredStart = end.addingTimeInterval(-SensorHistoryQuery.retention)
        var calls = 0
        let result = MotionHistoryProcessor.process(from: end, to: end, analyzer: .init(),
            pendingRanges: [.init(start: expiredStart, end: expiredStart.addingTimeInterval(600))],
            sensitivity: 0.5, query: { start, finish in
                guard let safe = SensorHistoryQuery.range(from: start, to: finish, now: self.now) else { return nil }
                calls += 1
                XCTAssertGreaterThan(safe.start, self.now.addingTimeInterval(-SensorHistoryQuery.retention))
                XCTAssertLessThanOrEqual(safe.end, self.now)
                return nil
            })
        XCTAssertGreaterThan(calls, 0)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.pendingRanges.isEmpty, "Missing source must remain visible, not become a smoke-free interval")
    }
}
