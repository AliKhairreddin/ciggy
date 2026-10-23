import Foundation
import XCTest
@testable import CiggyShared

final class CalibrationUploadPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEverySampleMustBeAfterConsentNotOnlyTheRecordingHeader() {
        let consent = now.addingTimeInterval(-100)
        var recording = fixture(start: consent)
        let name = filename(recording.id)
        guard case .eligible = CalibrationUploadPolicy.eligibility(recording, filename: name, consent: consent, now: now) else {
            return XCTFail("Valid post-consent samples should be eligible")
        }
        recording.samples[0] = sample(at: consent.addingTimeInterval(-0.5))
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: name, consent: consent, now: now), .beforeConsent)
    }

    func testOldHeaderOrAnyOldSampleExpiresAndFutureOrMalformedRecordingIsRejected() {
        let consent = now.addingTimeInterval(-72 * 3_600)
        let old = fixture(start: now.addingTimeInterval(-49 * 3_600))
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(old, filename: filename(old.id), consent: consent, now: now), .expired)
        var recording = fixture(start: now.addingTimeInterval(-60))
        recording.samples[0] = sample(at: now.addingTimeInterval(-49 * 3_600))
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: filename(recording.id), consent: consent, now: now), .expired)
        recording = fixture(start: now.addingTimeInterval(10))
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: filename(recording.id), consent: consent, now: now), .invalid)
        recording = fixture(start: now.addingTimeInterval(-60))
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: filename(UUID()), consent: consent, now: now), .invalid)
        recording.samples[1] = recording.samples[0]
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: filename(recording.id), consent: consent, now: now), .invalid)
    }

    func testHistoricalSourceCannotClaimMeasuredGyroscope() {
        var recording = fixture(start: now.addingTimeInterval(-60))
        recording.samples[0] = .init(timestamp: recording.startedAt, gravity: .init(x: 0, y: 0, z: -1),
                                     userAcceleration: .init(x: 0, y: 0, z: 0),
                                     rotationRate: .init(x: 0.1, y: 0, z: 0), source: .recordedAccelerometer)
        XCTAssertEqual(CalibrationUploadPolicy.eligibility(recording, filename: filename(recording.id),
                                                          consent: now.addingTimeInterval(-100), now: now), .invalid)
    }

    func testRetryAfterNumericAndHTTPDatePersistAndPauseOtherFiles() throws {
        let name = filename(UUID()), another = filename(UUID())
        var backoff = CalibrationUploadPolicy.Backoff()
        backoff.failed(name, status: 429, retryAfter: "3600", at: now)
        backoff = try JSONDecoder().decode(CalibrationUploadPolicy.Backoff.self, from: JSONEncoder().encode(backoff))
        XCTAssertFalse(backoff.allows(name, at: now.addingTimeInterval(3_599)))
        XCTAssertFalse(backoff.allows(another, at: now.addingTimeInterval(3_599)))
        XCTAssertTrue(backoff.allows(another, at: now.addingTimeInterval(3_601)))
        XCTAssertEqual(CalibrationUploadPolicy.retryDate("Tue, 14 Nov 2023 23:13:20 GMT", now: now), now.addingTimeInterval(3_600))
        backoff.failed(name, status: 503, retryAfter: "Tue, 14 Nov 2023 23:13:20 GMT", at: now)
        XCTAssertEqual(backoff.providerRetryAt, now.addingTimeInterval(3_600))
        backoff.succeeded(name)
        XCTAssertFalse(backoff.allows(another, at: now), "One successful receipt cannot bypass the provider's cooldown")
        backoff.prune(keeping: [], at: now.addingTimeInterval(3_601))
        XCTAssertNil(backoff.providerRetryAt)
    }

    func testMalformedRetryHeadersCannotTrapOrCreateInfiniteCooldown() {
        for header in ["NaN", "Infinity", "-1", "1e100", "invalid"] {
            XCTAssertNil(CalibrationUploadPolicy.retryDate(header, now: now))
        }
        let name = filename(UUID())
        var backoff = CalibrationUploadPolicy.Backoff()
        for _ in 0..<20 { backoff.failed(name, status: 500, retryAfter: nil, at: now) }
        XCTAssertEqual(backoff.failures[name]?.attempts, 8)
        XCTAssertEqual(backoff.failures[name]?.nextAttemptAt, now.addingTimeInterval(3_600))
    }

    func testOnlyReceiptMatchingTheOriginalUUIDCanAcknowledgeIt() throws {
        let id = UUID(), other = UUID()
        XCTAssertTrue(CalibrationUploadPolicy.receiptMatches(try JSONEncoder().encode(["recordingID": id.uuidString]), filename: filename(id)))
        XCTAssertFalse(CalibrationUploadPolicy.receiptMatches(try JSONEncoder().encode(["recordingID": other.uuidString]), filename: filename(id)))
        XCTAssertFalse(CalibrationUploadPolicy.receiptMatches(Data(#"{"ok":true}"#.utf8), filename: filename(id)))
        XCTAssertFalse(CalibrationUploadPolicy.receiptMatches(Data(), filename: "../motion-invalid.json"))
    }

    private func filename(_ id: UUID) -> String { "motion-\(id.uuidString).json" }
    private func sample(at date: Date) -> MotionSample {
        .init(timestamp: date, gravity: .init(x: 0, y: 0, z: -1), userAcceleration: .init(x: 0, y: 0, z: 0),
              rotationRate: nil, source: .recordedAccelerometer)
    }
    private func fixture(start: Date) -> MotionRecording {
        var recording = MotionRecording(label: .unlabelled, startedAt: start)
        recording.samples = [sample(at: start), sample(at: start.addingTimeInterval(0.1))]
        recording.endedAt = start.addingTimeInterval(0.1)
        return recording
    }
}
