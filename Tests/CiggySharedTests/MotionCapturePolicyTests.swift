import XCTest
@testable import CiggyShared

final class MotionCapturePolicyTests: XCTestCase {
    func testRenewalUsesRemainingWindowWithoutReissuingEveryMinute() {
        let now = Date()
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: nil))
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(-1)))
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(21_600)))
        XCTAssertFalse(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(43_140)))
    }
}
