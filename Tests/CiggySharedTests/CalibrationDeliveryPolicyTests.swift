import XCTest
@testable import CiggyShared

final class CalibrationDeliveryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testOnlyAcknowledgedSuccessStartsThirtyMinuteInterval() {
        var policy = CalibrationDeliveryPolicy()
        XCTAssertTrue(policy.shouldSchedule(at: now))
        policy.succeeded(at: now)
        XCTAssertFalse(policy.shouldSchedule(at: now.addingTimeInterval(1799)))
        XCTAssertTrue(policy.shouldSchedule(at: now.addingTimeInterval(1800)))
        XCTAssertFalse(CalibrationDeliveryPolicy.receiptMatches(Data("{\"saved\":false}".utf8)))
        XCTAssertFalse(CalibrationDeliveryPolicy.receiptMatches(Data("{}".utf8)))
        XCTAssertTrue(CalibrationDeliveryPolicy.receiptMatches(Data("{\"saved\":true}".utf8)))
    }

    func testFailureIsQueuedNowWithPersistedSystemRetryDeadline() throws {
        var policy = CalibrationDeliveryPolicy()
        policy.failed(at: now, retryAfter: "600")
        let restored = try JSONDecoder().decode(CalibrationDeliveryPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertTrue(restored.shouldSchedule(at: now), "A retry must be handed to URLSession before the app is suspended")
        XCTAssertEqual(restored.earliestBeginDate(at: now, providerRetryAt: nil), now.addingTimeInterval(600))
        XCTAssertEqual(restored.earliestBeginDate(at: now, providerRetryAt: now.addingTimeInterval(900)), now.addingTimeInterval(900))
        policy.succeeded(at: now.addingTimeInterval(600))
        XCTAssertNil(policy.retryAt)
        XCTAssertEqual(policy.failures, 0)
    }

    func testRepeatedFailuresBackOffAndClockRollbackDoesNotSuppressReports() {
        var policy = CalibrationDeliveryPolicy()
        for _ in 0..<30 { policy.failed(at: now, retryAfter: nil) }
        XCTAssertEqual(policy.failures, 8)
        XCTAssertEqual(policy.retryAt, now.addingTimeInterval(3600))
        policy.succeeded(at: now)
        XCTAssertTrue(policy.shouldSchedule(at: now.addingTimeInterval(-600)))
    }
}
