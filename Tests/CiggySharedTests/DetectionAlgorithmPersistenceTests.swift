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
        weak var previous = detector
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

    func testUnreadableLiveCheckpointRecoversAndSavesANewOne() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid".utf8), forKey: "live")
        let detector = DetectionAlgorithm(userDefaults: defaults, storageKey: "live")
        XCTAssertEqual(detector.sessionGestureCount, 0)
        await deliver(Date(), to: detector)
        let checkpoint = try XCTUnwrap(defaults.data(forKey: "live"))
        let engine = try JSONDecoder().decode(DetectionFusionEngine.self, from: checkpoint)
        XCTAssertEqual(engine.observedGestureCount, 1)
    }

    private func deliver(_ timestamp: Date, to detector: DetectionAlgorithm) async {
        let processed = expectation(description: "Live gesture processed")
        let subscription = detector.$sessionGestureCount.dropFirst().prefix(1).sink { _ in processed.fulfill() }
        MotionManager.shared.gestureDetected.send(timestamp)
        await fulfillment(of: [processed], timeout: 2)
        withExtendedLifetime(subscription) {}
    }
}
