import XCTest
@testable import CiggyShared

final class MotionCapturePolicyTests: XCTestCase {
    func testFifteenMinutePreferenceAdvancesOldHalfHourAppointment() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let preferred = now.addingTimeInterval(TrackingRefreshPolicy.preferredBackgroundInterval)
        XCTAssertEqual(preferred.timeIntervalSince(now), 900)
        XCTAssertTrue(MotionCapturePolicy.shouldSchedule(at: now, existing: now.addingTimeInterval(1_800), preferred: preferred))
        XCTAssertFalse(MotionCapturePolicy.shouldSchedule(at: now.addingTimeInterval(60), existing: preferred,
                                                         preferred: preferred.addingTimeInterval(60)))
    }

    func testFrequentOpensDoNotPostponeEarlierBackgroundRefresh() {
        let now = Date()
        let scheduled = now.addingTimeInterval(1_800)
        for minutes in 1..<30 {
            let openedAt = now.addingTimeInterval(Double(minutes) * 60)
            XCTAssertFalse(MotionCapturePolicy.shouldSchedule(at: openedAt, existing: scheduled,
                                                              preferred: openedAt.addingTimeInterval(1_800)))
        }
        for minutes in 0...120 {
            let overdue = scheduled.addingTimeInterval(Double(minutes) * 60)
            XCTAssertFalse(MotionCapturePolicy.shouldSchedule(at: overdue, existing: scheduled,
                                                              preferred: overdue.addingTimeInterval(1_800)))
        }
        let recovery = scheduled.addingTimeInterval(2 * 3_600 + 1)
        XCTAssertTrue(MotionCapturePolicy.shouldSchedule(at: recovery, existing: scheduled,
                                                         preferred: recovery.addingTimeInterval(1_800)))
    }

    func testRenewalUsesRemainingWindowWithoutReissuingEveryMinute() {
        let now = Date()
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: nil))
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(-1)))
        XCTAssertTrue(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(21_600)))
        XCTAssertFalse(MotionCapturePolicy.shouldRenew(at: now, armedUntil: now.addingTimeInterval(43_140)))
    }
}
