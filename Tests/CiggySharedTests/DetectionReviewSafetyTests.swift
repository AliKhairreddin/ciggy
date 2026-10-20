import XCTest
@testable import CiggyShared

@MainActor
final class DetectionReviewSafetyTests: XCTestCase {
    func testAdjustmentUsesNewlyMergedEventsInsteadOfStaleSheetSnapshot() throws {
        let suite = "DetectionReviewSafety.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = EventRepository(userDefaults: defaults, storageKey: "events")
        let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SmokingEvent(timestamp: date, source: .automatic)
        let second = SmokingEvent(timestamp: date.addingTimeInterval(60), source: .automatic)
        repository.addEvent(first)
        let snapshot = try XCTUnwrap(store.record(events: [first], origin: .liveWatch,
            windowStart: date, windowEnd: date))
        repository.addEvent(second)
        _ = store.record(events: [second], origin: .liveWatch, windowStart: date, windowEnd: second.timestamp)

        DetectionReviewWorkflow.adjust(snapshot, to: 1, repository: repository, store: store)

        XCTAssertEqual(repository.events, [first])
        XCTAssertEqual(store.latestReview?.displayCount, 1)
        XCTAssertFalse(repository.addEvent(second), "Delayed sync must not undo the correction.")
    }

    func testIncreasingInstantaneousReviewDoesNotInventFutureTimestamps() throws {
        let suite = "DetectionReviewSafety.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = EventRepository(userDefaults: defaults, storageKey: "events")
        let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let event = SmokingEvent(timestamp: date, source: .automatic)
        repository.addEvent(event)
        let review = try XCTUnwrap(store.record(events: [event], origin: .liveWatch,
            windowStart: date, windowEnd: date))
        DetectionReviewWorkflow.adjust(review, to: 3, repository: repository, store: store)
        XCTAssertEqual(repository.events.count, 3)
        XCTAssertTrue(repository.events.allSatisfy { $0.timestamp == date })
    }

    func testDecodedReviewNormalizesDuplicateIDsAndExtremeRevisionCannotOverflow() throws {
        let suite = "DetectionReviewSafety.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
        let date = Date()
        let eventID = UUID()
        var review = DetectionReview(eventIDs: [eventID], origin: .liveWatch,
            windowStart: date, windowEnd: date, revision: Int.max)
        review.eventIDs = [eventID, eventID]
        review.correctedCount = -99
        review.windowStart = date.addingTimeInterval(10)
        let decoded = try JSONDecoder().decode(DetectionReview.self, from: JSONEncoder().encode(review))
        XCTAssertEqual(decoded.eventIDs, [eventID])
        XCTAssertEqual(decoded.correctedCount, 0)
        XCTAssertLessThanOrEqual(decoded.windowStart, decoded.windowEnd)
        XCTAssertTrue(store.upsert(decoded))
        XCTAssertEqual(store.markAccurate(reviewID: review.id)?.revision, Int.max)
    }

    func testInvalidReviewDatesAreRejectedAndFormattingNeverTraps() throws {
        let suite = "DetectionReviewSafety.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
        var review = DetectionReview(eventIDs: [UUID()], origin: .watchHistory,
            windowStart: Date(), windowEnd: Date())
        review.windowEnd = Date(timeIntervalSinceReferenceDate: 1e100)
        XCTAssertGreaterThan(review.historyHours, 0)
        XCTAssertFalse(store.upsert(review))
        review.windowEnd = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertEqual(review.historyHours, 1)
        XCTAssertFalse(store.upsert(review))
        XCTAssertEqual(ChartHelpers.dayCounts(for: [], lastNDays: -1), [])
        XCTAssertTrue(SmokingEvent.mock(count: -1).isEmpty)
        XCTAssertEqual(Date(timeIntervalSinceReferenceDate: .nan).shortRelativeDescription(), "Unknown time")
        XCTAssertEqual(Date(timeIntervalSinceReferenceDate: -1e100).shortRelativeDescription(), "Unknown time")
    }
}
