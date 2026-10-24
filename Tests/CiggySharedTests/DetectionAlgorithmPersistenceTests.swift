import Combine
import XCTest
@testable import CiggyShared

@MainActor
final class DetectionAlgorithmPersistenceTests: XCTestCase {
    func testLivePartialPatternSurvivesRelaunch() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date()
        var detector: DetectionAlgorithm? = DetectionAlgorithm(userDefaults: defaults)
        for puff in 0..<3 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: detector!) }
        XCTAssertEqual(detector?.sessionGestureCount, 3)
        weak let previous = detector
        detector = nil
        XCTAssertNil(previous)
        let restored = DetectionAlgorithm(userDefaults: defaults)
        XCTAssertEqual(restored.sessionGestureCount, 3)
        var candidates: [DetectionCandidate] = []
        let subscription = restored.candidatePublisher.sink { candidates.append($0) }
        for puff in 3..<5 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: restored) }
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.motionSessionStartedAt, start)
        withExtendedLifetime(subscription) {}
    }

    func testCountedLivePatternCannotRestartAsAnotherCigaretteAfterRelaunch() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let start = Date()
        var detector: DetectionAlgorithm? = DetectionAlgorithm(userDefaults: defaults)
        for puff in 0..<10 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: detector!) }
        detector = nil
        let restored = DetectionAlgorithm(userDefaults: defaults)
        var candidates: [DetectionCandidate] = []
        let subscription = restored.candidatePublisher.sink { candidates.append($0) }
        for puff in 10..<30 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: restored) }
        XCTAssertTrue(candidates.isEmpty)
        for puff in 0..<5 { await deliver(start.addingTimeInterval(800 + Double(puff) * 20), to: restored) }
        XCTAssertEqual(candidates.count, 1)
        withExtendedLifetime(subscription) {}
    }

    func testUnreadableLiveCheckpointIsPreservedInsteadOfRestartingCountedSession() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let unreadable = Data("invalid".utf8)
        defaults.set(unreadable, forKey: "live")
        let detector = DetectionAlgorithm(userDefaults: defaults, storageKey: "live")
        XCTAssertNotNil(detector.lastPersistenceError)
        detector.updateSensitivity(multiplier: 0.5)
        let noCandidate = expectation(description: "Unreadable progress cannot create a fresh duplicate")
        noCandidate.isInverted = true
        let subscription = detector.candidatePublisher.sink { _ in noCandidate.fulfill() }
        let now = Date()
        for index in 0..<8 { MotionManager.shared.gestureDetected.send(now.addingTimeInterval(Double(index) * 20)) }
        await fulfillment(of: [noCandidate], timeout: 0.2)
        XCTAssertEqual(detector.sessionGestureCount, 0)
        XCTAssertEqual(defaults.data(forKey: "live"), unreadable)
        XCTAssertNotNil(detector.lastPersistenceError)
        withExtendedLifetime(subscription) {}
    }

    func testAtomicCountedSessionSurvivesWithoutAnyLegacyPreferences() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotURL = directory.appendingPathComponent("live.json")
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        let start = Date()
        var detector: DetectionAlgorithm? = DetectionAlgorithm(userDefaults: defaults, snapshotURL: snapshotURL)
        var initialCandidates: [DetectionCandidate] = []
        var initialSubscription: AnyCancellable? = detector?.candidatePublisher.sink { initialCandidates.append($0) }
        for puff in 0..<5 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: detector!) }
        XCTAssertEqual(initialCandidates.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        withExtendedLifetime(initialSubscription) {}
        initialSubscription = nil
        detector = nil
        defaults.removePersistentDomain(forName: name)

        let restored = DetectionAlgorithm(userDefaults: defaults, snapshotURL: snapshotURL)
        XCTAssertNil(restored.lastPersistenceError)
        var candidates: [DetectionCandidate] = []
        let subscription = restored.candidatePublisher.sink { candidates.append($0) }
        for puff in 5..<10 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: restored) }
        XCTAssertTrue(candidates.isEmpty, "The atomic checkpoint retains the already-counted session after an immediate restart.")
        withExtendedLifetime(subscription) {}
    }

    func testFailedCandidateJournalDoesNotConsumeTheLiveSession() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let detector = DetectionAlgorithm(userDefaults: defaults)
        let start = Date()
        var candidates: [DetectionCandidate] = []
        var attempts: [DetectionCandidate] = []
        var canPersist = false
        detector.persistCandidate = { candidate in attempts.append(candidate); return canPersist }
        let subscription = detector.candidatePublisher.sink { candidates.append($0) }
        for puff in 0..<5 { await deliver(start.addingTimeInterval(Double(puff) * 20), to: detector) }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(detector.sessionGestureCount, 4)
        XCTAssertTrue(candidates.isEmpty)

        canPersist = true
        await deliver(start.addingTimeInterval(100), to: detector)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.motionSessionStartedAt, start)
        await deliver(start.addingTimeInterval(120), to: detector)
        XCTAssertEqual(candidates.count, 1)
        withExtendedLifetime(subscription) {}
    }

    private func deliver(_ timestamp: Date, to detector: DetectionAlgorithm) async {
        let processed = expectation(description: "Live gesture processed")
        let subscription = detector.$sessionGestureCount.dropFirst().prefix(1).sink { _ in processed.fulfill() }
        MotionManager.shared.gestureDetected.send(timestamp)
        await fulfillment(of: [processed], timeout: 2)
        withExtendedLifetime(subscription) {}
    }
}
