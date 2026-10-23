import Foundation
import XCTest
@testable import CiggyShared

final class HistoricalCalibrationSamplerTests: XCTestCase {
    private let consent = Date(timeIntervalSince1970: 1_700_000_000.125)

    func testOnlyCompleteAvailablePostConsentWindowsAndRecentFirst() throws {
        let now = consent.addingTimeInterval(17 * 60)
        let windows = HistoricalCalibrationSampler.windows(enabledAt: consent, now: now)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.start), [consent.addingTimeInterval(300), consent])
        XCTAssertTrue(windows.allSatisfy { $0.start >= consent && $0.end <= now.addingTimeInterval(-180) })
        XCTAssertTrue(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(479)).isEmpty)
        XCTAssertEqual(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(480)).count, 1)
        XCTAssertEqual(windows.first?.id, HistoricalCalibrationSampler.windows(enabledAt: consent, now: now).first?.id)
        XCTAssertNotEqual(windows.first?.id,
                          HistoricalCalibrationSampler.windows(enabledAt: consent.addingTimeInterval(1), now: now).first?.id)
    }

    func testDownsamplesFiftyHzToTenAndPreservesUnitsSourceAndConsent() throws {
        let window = try XCTUnwrap(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(480)).first)
        let source = raw(from: consent.addingTimeInterval(-2), duration: 304)
        guard case .complete(let recording) = HistoricalCalibrationSampler.sample(AnySequence(source), window: window, enabledAt: consent) else {
            return XCTFail("Complete measured interval must export")
        }
        XCTAssertEqual(recording.id, window.id)
        XCTAssertEqual(recording.samples.count, 3_000)
        XCTAssertEqual(recording.startedAt, consent)
        XCTAssertEqual(recording.endedAt, window.end)
        XCTAssertEqual(recording.label, .unlabelled)
        XCTAssertEqual(recording.formatVersion, 1)
        XCTAssertTrue(recording.samples.allSatisfy { $0.timestamp >= consent && $0.timestamp < window.end && $0.rotationRate == nil && $0.source == .recordedAccelerometer })
        XCTAssertEqual(try XCTUnwrap(recording.samples.first).gravity.z, -1, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(recording.samples.first).userAcceleration.magnitude, 0, accuracy: 0.000_001)
        for pair in zip(recording.samples, recording.samples.dropFirst()) {
            XCTAssertEqual(pair.1.timestamp.timeIntervalSince(pair.0.timestamp), 0.1, accuracy: 0.000_001)
        }
    }

    func testMissingIsDifferentFromUsableFragmentsAndNoGapsAreFilled() throws {
        let window = try XCTUnwrap(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(480)).first)
        let complete = raw(from: consent, duration: 300)
        guard case .missing = HistoricalCalibrationSampler.sample(AnySequence([]), window: window, enabledAt: consent) else {
            return XCTFail("Empty source must stay pending")
        }
        let cases = [Array(complete.dropFirst(100)), Array(complete.dropLast(100)),
                     complete.filter { $0.timestamp < consent.addingTimeInterval(100) || $0.timestamp > consent.addingTimeInterval(103) }]
        for source in cases {
            guard case .partial(let recording) = HistoricalCalibrationSampler.sample(AnySequence(source), window: window, enabledAt: consent) else {
                return XCTFail("Available fragments must survive without completing the source window")
            }
            XCTAssertFalse(recording.samples.isEmpty)
            XCTAssertNotEqual(recording.id, window.id)
            XCTAssertTrue(recording.samples.allSatisfy { sample in source.contains { $0.timestamp == sample.timestamp } })
            if case .partial(let repeated) = HistoricalCalibrationSampler.sample(AnySequence(source), window: window, enabledAt: consent) {
                XCTAssertEqual(recording.id, repeated.id, "Unchanged fragments must not create repeated uploads")
            } else { XCTFail("Replay must preserve quality state") }
        }
        var invalid = complete
        invalid[1] = .init(timestamp: invalid[1].timestamp, x: .nan, y: 0, z: -1)
        guard case .partial = HistoricalCalibrationSampler.sample(AnySequence(invalid), window: window, enabledAt: consent) else {
            return XCTFail("Invalid sample is excluded while the remaining measured samples survive")
        }
    }

    func testClockJitterCannotRejectAnOtherwiseCompleteWindow() throws {
        let window = try XCTUnwrap(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(480)).first)
        let source = (0...15_000).map { RecordedAccelerationSample(timestamp: consent.addingTimeInterval(Double($0) * 0.019999995), x: 0, y: 0, z: -1) }
        guard case .complete(let recording) = HistoricalCalibrationSampler.sample(AnySequence(source), window: window, enabledAt: consent) else {
            return XCTFail("A tiny source-clock difference must not discard five minutes of motion")
        }
        XCTAssertEqual(recording.samples.count, 3_000)
    }

    func testPartialDoesNotCompleteLedgerAndMissingRetriesBackOffFromOneMinute() throws {
        let now = consent.addingTimeInterval(480)
        let window = try XCTUnwrap(HistoricalCalibrationSampler.windows(enabledAt: consent, now: now).first)
        guard case .partial(let recording) = HistoricalCalibrationSampler.sample(
            AnySequence(raw(from: consent.addingTimeInterval(10), duration: 290)), window: window, enabledAt: consent) else { return XCTFail() }
        var ledger = HistoricalCalibrationSampler.Ledger(enabledAt: consent)
        ledger.didQueuePartial(recording, for: window)
        XCTAssertNil(ledger.completed[window.id])
        var clock = now
        for delay in [60.0, 120, 240, 480, 900, 900] {
            ledger.retry(window, after: clock)
            XCTAssertEqual(ledger.retryAfter[window.id], clock.addingTimeInterval(delay))
            XCTAssertFalse(ledger.pending(now: clock.addingTimeInterval(delay - 1)).contains { $0.id == window.id })
            clock.addTimeInterval(delay)
        }
        ledger = try JSONDecoder().decode(HistoricalCalibrationSampler.Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(ledger.partialRecordingIDs?[window.id], recording.id)
        ledger.didComplete(window)
        XCTAssertNil(ledger.partialRecordingIDs?[window.id])
        XCTAssertFalse(ledger.pending(now: clock).contains { $0.id == window.id })
    }

    func testCancellationNeverReturnsPartialRecording() throws {
        let window = try XCTUnwrap(HistoricalCalibrationSampler.windows(enabledAt: consent, now: consent.addingTimeInterval(480)).first)
        var checks = 0
        let source = raw(from: consent, duration: 300)
        let result = HistoricalCalibrationSampler.sample(AnySequence(source), window: window, enabledAt: consent,
                                                         shouldContinue: { checks += 1; return checks < 3 })
        guard case .interrupted = result else { return XCTFail("Partial iteration must not complete") }
    }

    func testLedgerAvoidsCompletedPullsRetriesMissingAndExpiresAfterFortyEightHours() throws {
        let now = consent.addingTimeInterval(900)
        var ledger = HistoricalCalibrationSampler.Ledger(enabledAt: consent)
        let pending = ledger.pending(now: now)
        XCTAssertEqual(pending.count, 2)
        ledger.didComplete(pending[0])
        ledger.retry(pending[1], after: now)
        XCTAssertTrue(ledger.pending(now: now).isEmpty)
        XCTAssertFalse(ledger.pending(now: now.addingTimeInterval(901)).contains { $0.id == pending[0].id })
        XCTAssertTrue(ledger.pending(now: now.addingTimeInterval(901)).contains { $0.id == pending[1].id })
        ledger = try JSONDecoder().decode(HistoricalCalibrationSampler.Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(ledger.completed[pending[0].id], pending[0].end)
        let later = now.addingTimeInterval(49 * 3_600)
        ledger.reconcile(consent: consent, now: later)
        XCTAssertTrue(ledger.completed.isEmpty)
        XCTAssertTrue(ledger.retryAfter.isEmpty)
        XCTAssertLessThanOrEqual(ledger.pending(now: later).count, 576)
        XCTAssertTrue(ledger.pending(now: later).allSatisfy { $0.start >= later.addingTimeInterval(-48 * 3_600) })
        ledger.reconcile(consent: now, now: later)
        XCTAssertEqual(ledger.enabledAt, now)
    }

    private func raw(from start: Date, duration: TimeInterval) -> [RecordedAccelerationSample] {
        (0..<Int(duration * 50)).map {
            .init(timestamp: start.addingTimeInterval(Double($0) * 0.02), x: 0, y: 0, z: -1)
        }
    }
}
