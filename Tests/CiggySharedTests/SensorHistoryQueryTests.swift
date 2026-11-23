import XCTest
@testable import CiggyShared

final class SensorHistoryQueryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let threeDays: TimeInterval = 3 * 24 * 60 * 60

    func testDelayedAnalysisCutoffCannotProduceOutOfRetentionNativeQuery() throws {
        let analysisEnd = now.addingTimeInterval(-180)
        var currentTime = analysisEnd
        var requested: MotionHistoryRange?
        let sensor = SensorHistoryQuery(now: { currentTime }) { start, end in
            requested = .init(start: start, end: end)
            return nil
        }
        let oldReplayStart = analysisEnd.addingTimeInterval(-threeDays)
        let replayEnd = oldReplayStart.addingTimeInterval(1800)
        currentTime = now
        XCTAssertNil(sensor.samples(from: oldReplayStart, to: replayEnd))
        XCTAssertEqual(try XCTUnwrap(requested), .init(start: now.addingTimeInterval(-threeDays + 5), end: replayEnd))
    }

    func testExpiredAndInvalidQueriesNeverReachSensor() {
        let sensor = SensorHistoryQuery(now: { self.now }) { _, _ in
            XCTFail("An expired or invalid range reached the native sensor")
            return nil
        }
        let expired = now.addingTimeInterval(-threeDays)
        XCTAssertNil(sensor.samples(from: expired.addingTimeInterval(-600), to: expired))
        XCTAssertNil(sensor.samples(from: now, to: now))
        XCTAssertNil(sensor.samples(from: now.addingTimeInterval(10), to: now))
        XCTAssertNil(sensor.samples(from: Date(timeIntervalSince1970: .nan), to: now))
        XCTAssertNil(sensor.samples(from: now, to: .distantFuture))
    }

    func testRecentCalibrationWindowIsUnchangedAndOversizedQueriesAreBounded() {
        let start = now.addingTimeInterval(-600), end = now.addingTimeInterval(-300)
        let sample = RecordedAccelerationSample(timestamp: start, x: 0, y: 0, z: 1)
        var requests: [MotionHistoryRange] = []
        let sensor = SensorHistoryQuery(now: { self.now }) { start, end in
            requests.append(.init(start: start, end: end))
            return AnySequence([sample])
        }
        XCTAssertEqual(sensor.samples(from: start, to: end).map(Array.init), [sample])
        _ = sensor.samples(from: now.addingTimeInterval(-86400), to: now.addingTimeInterval(100))
        XCTAssertEqual(requests, [.init(start: start, end: end), .init(start: now.addingTimeInterval(-43200), end: now)])
    }

    func testSavedRepairReplayQueriesStaySafeWithoutChangingClassifier() {
        let end = now.addingTimeInterval(-180)
        let expiredStart = end.addingTimeInterval(-threeDays)
        var calls = 0
        let sensor = SensorHistoryQuery(now: { self.now }) { start, finish in
            calls += 1
            XCTAssertGreaterThan(start, self.now.addingTimeInterval(-self.threeDays))
            XCTAssertLessThanOrEqual(finish, self.now)
            return nil
        }
        let result = MotionHistoryProcessor.process(from: end, to: end, analyzer: .init(),
            pendingRanges: [.init(start: expiredStart, end: expiredStart.addingTimeInterval(600))],
            sensitivity: 0.5, query: sensor.samples(from:to:))
        XCTAssertGreaterThan(calls, 0)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertFalse(result.pendingRanges.isEmpty, "Missing source must remain visible, not become a smoke-free interval")
    }
}
