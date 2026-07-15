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

	func testDeletedEventTombstoneRejectsDelayedDuplicateDelivery() {
		let suiteName = "EventRepositoryTombstoneTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let event = SmokingEvent(id: UUID(), source: .automatic)
		let repository = EventRepository(userDefaults: defaults, storageKey: "events")

		XCTAssertTrue(repository.addEvent(event))
		XCTAssertTrue(repository.removeEvent(id: event.id))
		XCTAssertFalse(repository.addEvent(event))

		let restored = EventRepository(userDefaults: defaults, storageKey: "events")
		XCTAssertFalse(restored.addEvent(event))
		XCTAssertTrue(restored.events.isEmpty)
	}

	func testDetectionReviewMergesNearbyEventsAndPersistsAccurateDecision() {
		let suiteName = "DetectionReviewStoreTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "reviews"
		let start = Date(timeIntervalSince1970: 1_000)
		let first = SmokingEvent(timestamp: start, source: .automatic)
		let second = SmokingEvent(timestamp: start.addingTimeInterval(1_800), source: .automatic)
		let store = DetectionReviewStore(userDefaults: defaults, storageKey: key)

		let initial = store.record(
			events: [first],
			origin: .watchHistory,
			windowStart: start,
			windowEnd: start.addingTimeInterval(3_600),
			at: start.addingTimeInterval(3_601)
		)
		let merged = store.record(
			events: [second],
			origin: .watchHistory,
			windowStart: start.addingTimeInterval(1_800),
			windowEnd: start.addingTimeInterval(7_200),
			at: start.addingTimeInterval(7_201)
		)

		XCTAssertEqual(initial?.id, merged?.id)
		XCTAssertEqual(merged?.eventIDs, [first.id, second.id])
		XCTAssertEqual(merged?.historyHours, 2)
		let accurate = store.markAccurate(reviewID: try! XCTUnwrap(merged?.id))
		XCTAssertEqual(accurate?.decision, .accurate)
		XCTAssertEqual(
			DetectionReviewStore(userDefaults: defaults, storageKey: key).latestReview?.decision,
			.accurate
		)
	}

	func testAdjustingDetectionCountRemovesEventsAndPreventsTheirReturn() throws {
		let suiteName = "DetectionReviewAdjustmentTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let repository = EventRepository(userDefaults: defaults, storageKey: "events")
		let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
		let start = Date(timeIntervalSince1970: 1_000)
		let events = (0..<6).map {
			SmokingEvent(timestamp: start.addingTimeInterval(Double($0) * 600), source: .automatic)
		}
		events.forEach { repository.addEvent($0) }
		let review = try XCTUnwrap(store.record(
			events: events,
			origin: .watchHistory,
			windowStart: start,
			windowEnd: start.addingTimeInterval(8 * 3_600)
		))

		DetectionReviewWorkflow.adjust(review, to: 4, repository: repository, store: store)

		XCTAssertEqual(repository.events.count, 4)
		XCTAssertEqual(store.latestReview?.decision, .adjusted)
		XCTAssertEqual(store.latestReview?.displayCount, 4)
		XCTAssertFalse(repository.addEvent(events[5]))
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

	func testPendingCandidatesQueueInGestureOrder() {
		let suiteName = "DetectionCandidateQueueTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "pending"
		let later = DetectionCandidate(
			gestureAt: Date(timeIntervalSince1970: 200),
			detectedAt: Date(timeIntervalSince1970: 203)
		)
		let earlier = DetectionCandidate(
			gestureAt: Date(timeIntervalSince1970: 100),
			detectedAt: Date(timeIntervalSince1970: 103)
		)
		let store = DetectionCandidateStore(userDefaults: defaults, storageKey: key)

		XCTAssertTrue(store.present(later))
		XCTAssertTrue(store.present(earlier))
		XCTAssertFalse(store.present(earlier))
		XCTAssertEqual(store.pendingCandidates, [earlier, later])
		XCTAssertEqual(store.pendingCount, 2)

		XCTAssertTrue(store.resolve(candidateID: earlier.id))
		XCTAssertEqual(store.pendingCandidate, later)
		XCTAssertEqual(
			DetectionCandidateStore(userDefaults: defaults, storageKey: key).pendingCandidates,
			[later]
		)
	}

	func testPendingCandidateStoreMigratesLegacySingleCandidate() throws {
		let suiteName = "DetectionCandidateMigrationTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suiteName)!
		defer { defaults.removePersistentDomain(forName: suiteName) }
		let key = "pending"
		let candidate = DetectionCandidate(
			gestureAt: Date(timeIntervalSince1970: 100),
			detectedAt: Date(timeIntervalSince1970: 103)
		)
		defaults.set(try JSONEncoder().encode(candidate), forKey: key)

		let store = DetectionCandidateStore(userDefaults: defaults, storageKey: key)

		XCTAssertEqual(store.pendingCandidates, [candidate])
	}
}
