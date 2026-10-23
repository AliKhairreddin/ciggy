import XCTest
@testable import CiggyShared

@MainActor
final class TrackingStatusTests: XCTestCase {
    func testCalibrationStatusPreservesTransferStageAndConsentAcrossTransport() throws {
        let now = Date(timeIntervalSince1970: 1_792_785_600.125)
        let calibration = CalibrationTrackingStatus(enabledAt: now.addingTimeInterval(-600), checkedAt: now,
            latestQueuedMotionAt: now.addingTimeInterval(-10), pendingWindowCount: 1, retryingWindowCount: 1,
            queuedTransferCount: 2, lastError: nil)
        let status = TrackingStatus(generatedAt: now, captureAvailable: true, permissionGranted: true, calibration: calibration)
        let restored = try TrackingStatus.fromTransfer(status.transferData())
        XCTAssertEqual(restored.calibration, calibration)
        XCTAssertTrue(calibration.detail(consent: calibration.enabledAt!, now: now).contains("waiting to reach this iPhone"))
        XCTAssertFalse(calibration.detail(consent: calibration.enabledAt!, now: now).contains("uploaded"))
        XCTAssertTrue(calibration.detail(consent: now, now: now).contains("receive the sharing setting"))
        let legacy = TrackingStatus(generatedAt: now, captureAvailable: true, permissionGranted: true)
        XCTAssertNil(try TrackingStatus.fromTransfer(legacy.transferData()).calibration)
    }

    func testInvalidCalibrationTimestampCannotPoisonTrackingStatus() {
        let bad = CalibrationTrackingStatus(enabledAt: Date(timeIntervalSince1970: .nan), checkedAt: nil,
            latestQueuedMotionAt: nil, pendingWindowCount: 0, retryingWindowCount: 0, queuedTransferCount: 0, lastError: nil)
        XCTAssertFalse(TrackingStatus(captureAvailable: true, permissionGranted: true, calibration: bad).hasValidDates)
    }

    func testProcessingAndCompletionInSameSecondSurviveTransportInOrder() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 1_792_785_600.125)
        let checking = TrackingStatus(generatedAt: now, captureAvailable: true, permissionGranted: true, isProcessing: true)
        let complete = TrackingStatus(generatedAt: now.addingTimeInterval(0.05), historySampleAt: now.addingTimeInterval(-180),
                                       captureAvailable: true, permissionGranted: true)
        let store = TrackingStatusStore(defaults: defaults)
        XCTAssertTrue(store.receive(try .fromTransfer(checking.transferData())))
        XCTAssertTrue(store.receive(try .fromTransfer(complete.transferData())))
        XCTAssertEqual(store.status?.historySampleAt, complete.historySampleAt)
        XCTAssertEqual(store.status?.isProcessing, false)
    }

    func testOldDeliveryCannotReplaceNewerPersistedFreshness() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date()
        let fresh = TrackingStatus(generatedAt: now, historySampleAt: now.addingTimeInterval(-180),
                                   captureUntil: now.addingTimeInterval(43_200), captureAvailable: true, permissionGranted: true)
        let store = TrackingStatusStore(defaults: defaults)
        XCTAssertTrue(store.receive(fresh))
        XCTAssertFalse(store.receive(.init(generatedAt: now.addingTimeInterval(-60), captureAvailable: false, permissionGranted: false)))
        XCTAssertEqual(TrackingStatusStore(defaults: defaults).status, fresh)
    }

    func testArmedCaptureDoesNotImplyRecentCountsHaveBeenChecked() {
        let now = Date()
        let status = TrackingStatus(generatedAt: now, historySampleAt: now.addingTimeInterval(-3_600),
                                    captureUntil: now.addingTimeInterval(43_200), captureAvailable: true, permissionGranted: true)
        XCTAssertEqual(status.title(at: now), "Recent Watch data pending")
        XCTAssertTrue(status.detail(at: now).contains("may not be included yet"))
        XCTAssertFalse(status.detail(at: now).contains("up to date"))
    }

    func testExpiredCaptureAndMissingHistoryRemainVisible() {
        let now = Date()
        let status = TrackingStatus(generatedAt: now, historySampleAt: now.addingTimeInterval(-180),
                                    captureUntil: now.addingTimeInterval(-1), pendingHistory: true, expiredHistory: true,
                                    captureAvailable: true, permissionGranted: true)
        XCTAssertEqual(status.title(at: now), "Watch recording needs renewal")
        XCTAssertTrue(status.detail(at: now).contains("being retried"))
        XCTAssertTrue(status.detail(at: now).contains("expired"))
    }

    func testProcessingStateDoesNotStayStuckAfterWatchSuspension() {
        let now = Date()
        let status = TrackingStatus(generatedAt: now.addingTimeInterval(-90),
                                    captureUntil: now.addingTimeInterval(43_200),
                                    captureAvailable: true, permissionGranted: true, isProcessing: true)
        XCTAssertEqual(status.title(at: now), "Recent Watch data pending")
    }

    func testRefreshRequestsAreBoundedButClockChangesCanRecover() {
        let now = Date()
        XCTAssertTrue(HistoryRefreshPolicy.shouldRequest(at: now, lastRequestedAt: nil))
        XCTAssertFalse(HistoryRefreshPolicy.shouldRequest(at: now.addingTimeInterval(59), lastRequestedAt: now))
        XCTAssertTrue(HistoryRefreshPolicy.shouldRequest(at: now.addingTimeInterval(60), lastRequestedAt: now))
        XCTAssertTrue(HistoryRefreshPolicy.shouldRequest(at: now.addingTimeInterval(-1), lastRequestedAt: now))
    }
}
