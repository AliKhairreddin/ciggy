import XCTest
@testable import CiggyShared

final class MotionCapturePolicyTests: XCTestCase {
    func testRefreshIgnoredWhileForegroundedGetsAReplacementOnBackgroundEntry() {
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let appointment = openedAt.addingTimeInterval(900)
        let backgroundedAt = openedAt.addingTimeInterval(960)
        var pending: Date? = appointment
        // The ordinary scheduler preserves an overdue request for two hours.
        XCTAssertFalse(MotionCapturePolicy.shouldSchedule(at: backgroundedAt, existing: pending,
            preferred: backgroundedAt.addingTimeInterval(900)))
        if MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: pending,
            foregroundStartedAt: openedAt, endedAt: backgroundedAt) {
            pending = nil
        }
        XCTAssertTrue(MotionCapturePolicy.shouldSchedule(at: backgroundedAt, existing: pending,
            preferred: backgroundedAt.addingTimeInterval(900)))
    }

    func testForegroundExitPreservesEarlierOverdueAndFutureAppointments() {
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let closedAt = openedAt.addingTimeInterval(60)
        for appointment in [openedAt.addingTimeInterval(-60), closedAt.addingTimeInterval(60)] {
            XCTAssertFalse(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: appointment,
                foregroundStartedAt: openedAt, endedAt: closedAt))
        }
        XCTAssertTrue(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: closedAt,
            foregroundStartedAt: openedAt, endedAt: closedAt))
    }

    func testUnknownForegroundSessionOrInvalidClockCannotDiscardAppointment() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: date,
            foregroundStartedAt: nil, endedAt: date))
        XCTAssertFalse(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: nil,
            foregroundStartedAt: date, endedAt: date))
        XCTAssertFalse(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: date,
            foregroundStartedAt: date, endedAt: date.addingTimeInterval(-1)))
        XCTAssertFalse(MotionCapturePolicy.wasRefreshDueDuringForeground(scheduledAt: date,
            foregroundStartedAt: date, endedAt: Date(timeIntervalSince1970: .nan)))
    }

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
