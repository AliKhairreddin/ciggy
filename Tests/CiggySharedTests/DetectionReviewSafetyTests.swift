import XCTest
@testable import CiggyShared

@MainActor
final class DetectionReviewSafetyTests: XCTestCase {
    private func withStore(_ body: (DetectionReviewStore, UserDefaults) throws -> Void) throws {
        let suite = "DetectionReviewSafety.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(DetectionReviewStore(userDefaults: defaults, storageKey: "reviews"), defaults)
    }

    func testPendingReplayCannotReopenAUserDecisionInEitherDeliveryOrder() throws {
        for decision in [DetectionReviewDecision.accurate, .adjusted] {
            try withStore { first, _ in
                try withStore { second, _ in
                    let date = Date(timeIntervalSince1970: 1_800_000_000)
                    var pending = DetectionReview(eventIDs: [UUID()], origin: .liveWatch,
                        windowStart: date, windowEnd: date, updatedAt: date, revision: 1)
                    var decided = pending
                    decided.decision = decision
                    decided.correctedCount = decision == .adjusted ? 0 : nil
                    decided.reviewedAt = date.addingTimeInterval(1)
                    decided.updatedAt = date.addingTimeInterval(1)
                    decided.revision = 2
                    pending.updatedAt = date.addingTimeInterval(2)
                    pending.revision = 3

                    first.upsert(decided)
                    XCTAssertFalse(first.upsert(pending))
                    second.upsert(pending)
                    XCTAssertTrue(second.upsert(decided))

                    XCTAssertEqual(first.reviews, [decided])
                    XCTAssertEqual(second.reviews, first.reviews)
                    XCTAssertNil(first.markAdjusted(reviewID: decided.id, correctedCount: 2))
                }
            }
        }
    }

    func testConcurrentPendingExtensionsConvergeWithoutLosingNewDetections() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let day = Calendar.current.startOfDay(for: date)
        let ids = [UUID(), UUID(), UUID()]
        let decided = DetectionReview(eventIDs: [ids[0]], origin: .watchHistory,
            windowStart: date, windowEnd: date, decision: .adjusted, correctedCount: 0,
            reviewedAt: date.addingTimeInterval(1), updatedAt: date.addingTimeInterval(1),
            revision: 2, dayStart: day)
        let extensions = [2, 3].map { count in
            DetectionReview(id: decided.id, eventIDs: Array(ids.prefix(count)), origin: .watchHistory,
                windowStart: date, windowEnd: date.addingTimeInterval(Double(count) * 60),
                updatedAt: date.addingTimeInterval(Double(count) * 60), revision: count + 1, dayStart: day)
        }
        var expected: [DetectionReview]?
        let deliveries = [
            [decided, extensions[0], extensions[1]],
            [extensions[0], decided, extensions[1]],
            [extensions[0], extensions[1], decided],
            [extensions[1], decided, extensions[0]],
            [decided, extensions[1], extensions[0]]
        ]
        for delivery in deliveries {
            try withStore { store, defaults in
                delivery.forEach { store.upsert($0) }
                XCTAssertEqual(store.reviews.count, 2)
                XCTAssertEqual(store.reviews.first(where: { $0.id == decided.id }), decided)
                let continuation = try XCTUnwrap(store.reviews.first(where: { $0.decision == .pending }))
                XCTAssertEqual(continuation.eventIDs, Array(ids.dropFirst()))
                XCTAssertEqual(continuation.dayStart, day)
                XCTAssertNil(continuation.parentReviewID, "A continuation must not hide its saved decision.")
                XCTAssertEqual(store.reviews(on: day).count, 2)
                XCTAssertTrue(store.normalizePendingReviews(events: []).isEmpty)
                if let expected { XCTAssertEqual(store.reviews, expected) }
                else { expected = store.reviews }
                for replay in delivery { XCTAssertFalse(store.upsert(replay)) }
                XCTAssertEqual(DetectionReviewStore(userDefaults: defaults, storageKey: "reviews").reviews, expected)
            }
        }
    }

    func testDelayedParentAndNewContinuationDetectionsBothSurvive() throws {
        try withStore { store, _ in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let ids = [UUID(), UUID(), UUID(), UUID()]
            let decided = DetectionReview(eventIDs: [ids[0]], origin: .liveWatch,
                windowStart: date, windowEnd: date, decision: .accurate,
                updatedAt: date, revision: 2, dayStart: Calendar.current.startOfDay(for: date))
            var pending = DetectionReview(id: decided.id, eventIDs: Array(ids.prefix(2)), origin: .liveWatch,
                windowStart: date, windowEnd: date.addingTimeInterval(60),
                updatedAt: date.addingTimeInterval(60), revision: 3, dayStart: decided.dayStart)
            store.upsert(decided)
            store.upsert(pending)
            let continuation = try XCTUnwrap(store.reviews.first { $0.decision == .pending })
            var newerContinuation = continuation
            newerContinuation.eventIDs.append(ids[3])
            newerContinuation.revision = 4
            newerContinuation.updatedAt = date.addingTimeInterval(180)
            newerContinuation.windowEnd = newerContinuation.updatedAt
            store.upsert(newerContinuation)
            pending.eventIDs.append(ids[2])
            pending.revision = 4
            pending.updatedAt = date.addingTimeInterval(120)
            pending.windowEnd = pending.updatedAt
            XCTAssertTrue(store.upsert(pending))
            let merged = try XCTUnwrap(store.reviews.first { $0.id == continuation.id })
            XCTAssertEqual(Set(merged.eventIDs), Set(ids.dropFirst()))
            XCTAssertEqual(merged.windowEnd, newerContinuation.windowEnd)
            XCTAssertFalse(store.upsert(pending))
            XCTAssertFalse(store.upsert(newerContinuation))

            try withStore { reverse, _ in
                reverse.upsert(decided)
                reverse.upsert(pending)
                reverse.upsert(newerContinuation)
                XCTAssertEqual(reverse.reviews, store.reviews)
            }
        }
    }

    func testResolvedContinuationStaysResolvedWhenOriginalSummaryIsReplayed() throws {
        try withStore { store, defaults in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let ids = [UUID(), UUID(), UUID()]
            let decided = DetectionReview(eventIDs: [ids[0]], origin: .liveWatch,
                windowStart: date, windowEnd: date, decision: .accurate,
                reviewedAt: date, updatedAt: date, revision: 2,
                dayStart: Calendar.current.startOfDay(for: date))
            var pending = DetectionReview(id: decided.id, eventIDs: Array(ids.prefix(2)), origin: .liveWatch,
                windowStart: date, windowEnd: date.addingTimeInterval(60),
                updatedAt: date.addingTimeInterval(60), revision: 3, dayStart: decided.dayStart)
            store.upsert(decided)
            store.upsert(pending)
            let continuation = try XCTUnwrap(store.reviews.first { $0.decision == .pending })
            let saved = try XCTUnwrap(store.markAdjusted(reviewID: continuation.id, correctedCount: 0,
                at: date.addingTimeInterval(90)))
            let restored = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
            XCTAssertFalse(restored.upsert(pending))
            pending.eventIDs.append(ids[2])
            pending.revision = 4
            pending.updatedAt = date.addingTimeInterval(120)
            pending.windowEnd = pending.updatedAt
            XCTAssertTrue(restored.upsert(pending))
            XCTAssertEqual(restored.reviews.count, 3)
            XCTAssertEqual(restored.reviews.first { $0.id == continuation.id }, saved)
            XCTAssertEqual(restored.reviews.first { $0.decision == .pending }?.eventIDs, [ids[2]])
            XCTAssertFalse(restored.upsert(pending))
            XCTAssertEqual(DetectionReviewStore(userDefaults: defaults, storageKey: "reviews").reviews, restored.reviews)
        }
    }

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
