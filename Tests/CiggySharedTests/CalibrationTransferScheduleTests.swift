import XCTest
@testable import CiggyShared

final class CalibrationTransferScheduleTests: XCTestCase {
    func testOldMotionDoesNotWaitAnotherHourAfterLateExtractionOrEmptyQueue() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var schedule = CalibrationTransferSchedule()
        schedule.releaseIfDue(pending: ["old"], at: now, oldestRecordingAt: now.addingTimeInterval(-7200))
        XCTAssertEqual(schedule.releasedPaths, ["old"])
        XCTAssertEqual(schedule.lastBatchAt, now)
        schedule.reconcile(pending: [], at: now)
        schedule = try JSONDecoder().decode(CalibrationTransferSchedule.self, from: JSONEncoder().encode(schedule))
        schedule.releaseIfDue(pending: ["more-old"], at: now.addingTimeInterval(1), oldestRecordingAt: now.addingTimeInterval(-7000))
        XCTAssertTrue(schedule.releasedPaths.isEmpty, "An old backlog must not create repeated immediate batches")
        schedule.releaseIfDue(pending: ["more-old"], at: now.addingTimeInterval(3600), oldestRecordingAt: now.addingTimeInterval(-7000))
        XCTAssertEqual(schedule.releasedPaths, ["more-old"])
    }

    func testLegacyScheduleAndContainerUpdatePreserveReleasedFiles() throws {
        let name = "calibration_1790000000000_\(UUID().uuidString).json"
        let old = "/old-container/Library/Application Support/CiggyHistoricalCalibration/\(name)"
        let directory = URL(fileURLWithPath: "/new-container/Library/Application Support/CiggyHistoricalCalibration")
        let relocated = CalibrationRecordingPath.relocate(old, directory: directory)
        XCTAssertEqual(relocated, directory.appendingPathComponent(name).path)
        let legacy = try JSONSerialization.data(withJSONObject: ["releasedPaths": [old], "nextBatchAt": 800000000])
        var schedule = try JSONDecoder().decode(CalibrationTransferSchedule.self, from: legacy)
        XCTAssertNil(schedule.lastBatchAt)
        schedule.relocatePaths([old: relocated])
        schedule.reconcile(pending: [relocated], at: Date(timeIntervalSinceReferenceDate: 799999999))
        XCTAssertEqual(schedule.releasedPaths, [relocated])
        XCTAssertEqual(CalibrationRecordingPath.endDate(filename: name), Date(timeIntervalSince1970: 1790000000))
        for path in ["/other/\(name)", "/CiggyHistoricalCalibration/ledger.json", "/CiggyHistoricalCalibration/calibration_nan_bad.json"] {
            XCTAssertEqual(CalibrationRecordingPath.relocate(path, directory: directory), path)
        }
    }

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
