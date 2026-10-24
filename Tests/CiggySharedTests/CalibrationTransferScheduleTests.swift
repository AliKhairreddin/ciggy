import XCTest
@testable import CiggyShared

final class CalibrationTransferScheduleTests: XCTestCase {
    func testHourlyReleaseSurvivesRelaunchAndKeepsNewFilesForNextBatch() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var schedule = CalibrationTransferSchedule()
        schedule.reconcile(pending: ["first"], at: start)
        schedule.releaseIfDue(pending: ["first"], at: start.addingTimeInterval(3599))
        XCTAssertTrue(schedule.releasedPaths.isEmpty)
        schedule = try JSONDecoder().decode(CalibrationTransferSchedule.self, from: JSONEncoder().encode(schedule))
        schedule.releaseIfDue(pending: ["first"], at: start.addingTimeInterval(3600))
        XCTAssertEqual(schedule.releasedPaths, ["first"])
        schedule.releaseIfDue(pending: ["first", "second"], at: start.addingTimeInterval(3601))
        XCTAssertEqual(schedule.releasedPaths, ["first"])
        schedule.releaseIfDue(pending: ["second"], at: start.addingTimeInterval(7200))
        XCTAssertEqual(schedule.releasedPaths, ["second"])
    }

    func testMissedWakesReleaseOneSavedBatchAndOptOutClearsEligibility() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var schedule = CalibrationTransferSchedule()
        schedule.reconcile(pending: ["a", "b"], at: start)
        schedule.releaseIfDue(pending: ["a", "b"], at: start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(schedule.releasedPaths, ["a", "b"])
        XCTAssertEqual(schedule.nextBatchAt, start.addingTimeInterval(7 * 3600))
        schedule.reconcile(pending: [], at: start.addingTimeInterval(6 * 3600))
        XCTAssertTrue(schedule.releasedPaths.isEmpty)
        XCTAssertNil(schedule.nextBatchAt)
        schedule.reconcile(pending: ["new-consent"], at: start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(schedule.nextBatchAt, start.addingTimeInterval(7 * 3600))
        XCTAssertTrue(schedule.releasedPaths.isEmpty)
    }
}
