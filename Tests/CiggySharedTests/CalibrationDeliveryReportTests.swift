import XCTest
@testable import CiggyShared

final class CalibrationDeliveryReportTests: XCTestCase {
    func testReportUsesMillisecondsAndDoesNotExportWatchErrors() throws {
        let now = Date(timeIntervalSince1970: 1790000000), consent = Date(timeIntervalSince1970: 1789990000.12)
        let status = CalibrationTrackingStatus(enabledAt: consent, checkedAt: now, latestQueuedMotionAt: now,
            pendingWindowCount: 4, retryingWindowCount: 2, queuedTransferCount: 1, lastError: "private error text",
            nextBatchAt: now.addingTimeInterval(3600), lastBatchAt: now, lastDeliveredAt: now, build: "13")
        let report = CalibrationDeliveryReport(observedAt: now, consentAt: consent, phoneBuild: "13",
            phoneLastReceivedAt: now, phoneLastUploadedAt: nil, phonePendingCount: 2, phoneScheduledCount: 2,
            phoneRetryAt: nil, watchStatus: status)
        let data = try report.encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "deliveryStatus")
        XCTAssertEqual(json["observedAt"] as? Double, 1790000000000)
        XCTAssertEqual(report.watch?.queuedTransferCount, 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private error"))
        let old = CalibrationDeliveryReport(observedAt: now, consentAt: now, phoneBuild: "13",
            phoneLastReceivedAt: nil, phoneLastUploadedAt: nil, phonePendingCount: 0, phoneScheduledCount: 0,
            phoneRetryAt: nil, watchStatus: status)
        XCTAssertNil(old.watch, "A previous consent's Watch report must not be attributed to this enrollment")
    }

    func testOlderWatchStatusStillDecodesWithoutNewFields() throws {
        let data = Data(#"{"enabledAt":800000000,"checkedAt":800000001,"pendingWindowCount":2,"retryingWindowCount":0,"queuedTransferCount":1}"#.utf8)
        let status = try JSONDecoder().decode(CalibrationTrackingStatus.self, from: data)
        XCTAssertNil(status.nextBatchAt)
        XCTAssertNil(status.build)
        XCTAssertTrue(status.hasValidDates)
    }
}
