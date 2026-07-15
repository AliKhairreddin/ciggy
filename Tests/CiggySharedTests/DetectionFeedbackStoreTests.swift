import XCTest
@testable import CiggyShared

@MainActor
final class DetectionFeedbackStoreTests: XCTestCase {
	func testNotificationsRequireOptInByDefault() {
		XCTAssertFalse(UserSettings().notificationsEnabled)
	}

	func testRecordsOnlyOneDecisionPerCandidateAndPersistsIt() {
		let suiteName = "DetectionFeedbackStoreTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "feedback"
		let candidate = DetectionCandidate(
			gestureAt: Date(timeIntervalSince1970: 100),
			detectedAt: Date(timeIntervalSince1970: 103),
			baselineHeartRate: 70,
			peakHeartRate: 82
		)
		let store = DetectionFeedbackStore(userDefaults: defaults, storageKey: key)

		store.record(candidate: candidate, decision: .dismissed)
		store.record(candidate: candidate, decision: .confirmed)

		XCTAssertEqual(store.feedback.count, 1)
		XCTAssertEqual(store.feedback.first?.decision, .dismissed)
		let reloaded = DetectionFeedbackStore(userDefaults: defaults, storageKey: key)
		XCTAssertEqual(reloaded.feedback, store.feedback)
	}

	func testFreshEventRepositoryDoesNotClaimAStreakOrSavings() {
		let suiteName = "EventRepositoryTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let repository = EventRepository(userDefaults: defaults, storageKey: "events")

		XCTAssertEqual(repository.streakSmokeFreeDays(), 0)
		XCTAssertEqual(repository.estimatedMoneySaved(), 0)
	}

	func testDuplicateConnectivityDeliveryAddsEventOnlyOnce() {
		let suiteName = "EventRepositoryDeduplicationTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let repository = EventRepository(userDefaults: defaults, storageKey: "events")
		let event = SmokingEvent(id: UUID(), source: .manual)

		repository.addEvent(event)
		repository.addEvent(event)

		XCTAssertEqual(repository.events, [event])
	}

	func testPendingCandidateSurvivesRelaunchAndClearsOnDecision() {
		let suiteName = "DetectionCandidateStoreTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "pending"
		let candidate = DetectionCandidate(
			gestureAt: Date(timeIntervalSince1970: 100),
			detectedAt: Date(timeIntervalSince1970: 103),
			baselineHeartRate: 70,
			peakHeartRate: 82
		)

		let originalStore = DetectionCandidateStore(userDefaults: defaults, storageKey: key)
		XCTAssertTrue(originalStore.present(candidate))
		let restoredStore = DetectionCandidateStore(userDefaults: defaults, storageKey: key)
		XCTAssertEqual(restoredStore.pendingCandidate, candidate)
		XCTAssertTrue(restoredStore.resolve(candidateID: candidate.id))
		XCTAssertNil(DetectionCandidateStore(userDefaults: defaults, storageKey: key).pendingCandidate)
	}
}
