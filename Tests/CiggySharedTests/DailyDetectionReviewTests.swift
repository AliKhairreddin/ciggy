import XCTest
@testable import CiggyShared

@MainActor
final class DailyDetectionReviewTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ hour: Int, day: Int = 23) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func withStore(_ body: (DetectionReviewStore, UserDefaults) throws -> Void) throws {
        let suite = "DailyDetectionReview.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(DetectionReviewStore(userDefaults: defaults, storageKey: "reviews"), defaults)
    }

    func testNoDetectionsCreatesNoReviewAndNewDetectionsMergeUntilReviewed() throws {
        try withStore { store, _ in
            XCTAssertTrue(store.recordDaily(events: [], origin: .watchHistory,
                windowStart: date(0), windowEnd: date(10), calendar: calendar).isEmpty)
            XCTAssertTrue(store.reviews.isEmpty)
            let first = SmokingEvent(timestamp: date(18), source: .automatic)
            let second = SmokingEvent(timestamp: date(19), source: .automatic)
            let initial = try XCTUnwrap(store.recordDaily(events: [first], origin: .watchHistory,
                windowStart: date(0), windowEnd: date(18), calendar: calendar).first)
            let merged = try XCTUnwrap(store.recordDaily(events: [second], origin: .watchHistory,
                windowStart: date(18), windowEnd: date(20), calendar: calendar).first)
            XCTAssertEqual(merged.id, initial.id)
            XCTAssertEqual(merged.eventIDs, [first.id, second.id])
            XCTAssertNotNil(store.markAccurate(reviewID: merged.id))
            let third = SmokingEvent(timestamp: date(21), source: .automatic)
            let next = try XCTUnwrap(store.recordDaily(events: [third], origin: .watchHistory,
                windowStart: date(20), windowEnd: date(22), calendar: calendar).first)
            XCTAssertNotEqual(next.id, initial.id)
            XCTAssertEqual(next.eventIDs, [third.id])
        }
    }

    func testReviewShowsDetectionTimesInsteadOfMidnightBacklogOrDeliveryTime() throws {
        try withStore { store, defaults in
            let event = SmokingEvent(timestamp: date(18), source: .automatic)
            let review = try XCTUnwrap(store.recordDaily(events: [event], origin: .watchHistory,
                windowStart: date(0), windowEnd: date(21), at: date(23), calendar: calendar).first)
            XCTAssertEqual(review.estimatedLogRange, date(18)...date(18))
            let summary = review.timingSummary(now: date(23), calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
            XCTAssertTrue(summary.hasPrefix("Estimated logs: Today"))
            XCTAssertFalse(summary.contains("12:00"))
            XCTAssertFalse(summary.contains(" – "))
            // Presentation must not rewrite the original correction scope or sync state.
            XCTAssertEqual(review.windowStart, date(0))
            XCTAssertEqual(review.windowEnd, date(21))
            let restored = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
            XCTAssertEqual(restored.latestReview, review)
        }
    }

    func testIncompleteSnapshotsUseExplicitReviewPeriodAndIgnoreUnrelatedEvents() {
        let first = SmokingEvent(timestamp: date(18), source: .automatic)
        let second = SmokingEvent(timestamp: date(20), source: .automatic)
        let unrelated = SmokingEvent(timestamp: date(0), source: .automatic)
        var review = DetectionReview(eventIDs: [first.id, second.id], origin: .watchHistory,
            windowStart: date(0), windowEnd: date(22), eventSnapshots: [first, unrelated])
        XCTAssertNil(review.estimatedLogRange)
        XCTAssertTrue(review.timingSummary().hasPrefix("Review period:"))
        review.eventSnapshots.append(second)
        XCTAssertEqual(review.estimatedLogRange, date(18)...date(20))
        review.decision = .adjusted
        review.correctedCount = 4
        XCTAssertTrue(review.timingSummary().hasPrefix("Original estimates:"))
    }

    func testBacklogIsPartitionedByEventDayAndWindowsNeverCrossMidnight() throws {
        try withStore { store, _ in
            let yesterday = SmokingEvent(timestamp: date(23, day: 22), source: .automatic)
            let today = SmokingEvent(timestamp: date(1), source: .automatic)
            let recorded = store.recordDaily(events: [today, yesterday], origin: .watchHistory,
                windowStart: date(12, day: 22), windowEnd: date(12), calendar: calendar)

            XCTAssertEqual(recorded.count, 2)
            XCTAssertEqual(store.reviews(on: date(12), calendar: calendar).first?.eventIDs, [today.id])
            XCTAssertEqual(store.previousReviews(before: date(12), calendar: calendar).first?.eventIDs, [yesterday.id])
            for review in recorded {
                XCTAssertTrue(calendar.isDate(review.windowStart, inSameDayAs: review.windowEnd))
                XCTAssertTrue(calendar.isDate(try XCTUnwrap(review.dayStart), inSameDayAs: review.windowEnd))
            }
        }
    }

    func testYesterdayArrivingLaterDoesNotReplaceTodaysReview() throws {
        try withStore { store, _ in
            let today = SmokingEvent(timestamp: date(10), source: .automatic)
            let yesterday = SmokingEvent(timestamp: date(18, day: 22), source: .automatic)
            _ = store.recordDaily(events: [today], origin: .watchHistory,
                windowStart: today.timestamp, windowEnd: today.timestamp, at: date(11), calendar: calendar)
            _ = store.recordDaily(events: [yesterday], origin: .watchHistory,
                windowStart: yesterday.timestamp, windowEnd: yesterday.timestamp, at: date(12), calendar: calendar)

            XCTAssertEqual(store.latestReview(on: date(12), calendar: calendar)?.eventIDs, [today.id])
        }
    }

    func testLegacyMigrationWaitsForEventsAndIsDeterministicAcrossDevices() throws {
        try withStore { first, _ in
            try withStore { second, _ in
                let yesterday = SmokingEvent(timestamp: date(23, day: 22), source: .automatic)
                let today = SmokingEvent(timestamp: date(1), source: .automatic)
                let legacy = DetectionReview(eventIDs: [yesterday.id, today.id], origin: .watchHistory,
                    windowStart: date(12, day: 22), windowEnd: date(12), updatedAt: date(12))
                first.upsert(legacy)
                second.upsert(legacy)

                XCTAssertTrue(first.normalizePendingReviews(events: [today], calendar: calendar).isEmpty)
                XCTAssertTrue(first.reviews(on: date(12), calendar: calendar).isEmpty)
                let children = first.normalizePendingReviews(events: [yesterday, today], calendar: calendar)
                let otherChildren = second.normalizePendingReviews(events: [today, yesterday], calendar: calendar)
                XCTAssertEqual(children, otherChildren)
                XCTAssertEqual(children.count, 2)
                XCTAssertTrue(first.normalizePendingReviews(events: [yesterday, today], calendar: calendar).isEmpty)
                XCTAssertNil(first.markAccurate(reviewID: legacy.id), "A stale cross-day sheet must not correct the parent.")
                XCTAssertEqual(first.reviews(on: date(12), calendar: calendar).first?.eventIDs, [today.id])
            }
        }
    }

    func testCorrectingTodayCannotDeleteYesterdaysEvents() throws {
        try withStore { store, defaults in
            let repository = EventRepository(userDefaults: defaults, storageKey: "events")
            let yesterday = SmokingEvent(timestamp: date(23, day: 22), source: .automatic)
            let today = SmokingEvent(timestamp: date(1), source: .automatic)
            repository.addEvent(yesterday)
            repository.addEvent(today)
            let daily = store.recordDaily(events: [yesterday, today], origin: .watchHistory,
                windowStart: date(12, day: 22), windowEnd: date(12), calendar: calendar)
            let todayReview = try XCTUnwrap(daily.last)

            DetectionReviewWorkflow.adjust(todayReview, to: 0, repository: repository, store: store)

            XCTAssertEqual(repository.events, [yesterday])
            XCTAssertEqual(store.reviews(on: date(12), calendar: calendar).first?.displayCount, 0)
        }
    }

    func testAddingMissingCigarettesStaysInsideSelectedDay() throws {
        try withStore { store, defaults in
            let repository = EventRepository(userDefaults: defaults, storageKey: "events")
            let event = SmokingEvent(timestamp: date(1), source: .automatic)
            repository.addEvent(event)
            let review = try XCTUnwrap(store.recordDaily(events: [event], origin: .watchHistory,
                windowStart: date(12, day: 22), windowEnd: date(12), calendar: calendar).first)

            DetectionReviewWorkflow.adjust(review, to: 4, repository: repository, store: store)

            XCTAssertEqual(repository.events.count, 4)
            XCTAssertTrue(repository.events.allSatisfy { calendar.isDate($0.timestamp, inSameDayAs: date(12)) })
        }
    }

    func testMigratedParentStaysHiddenAfterRelaunchAndDelayedReplay() throws {
        try withStore { store, defaults in
            let event = SmokingEvent(timestamp: date(1), source: .automatic)
            var legacy = DetectionReview(eventIDs: [event.id], origin: .watchHistory,
                windowStart: date(12, day: 22), windowEnd: date(12), updatedAt: date(12))
            store.upsert(legacy)
            let child = try XCTUnwrap(store.normalizePendingReviews(events: [event], calendar: calendar).first)
            let restored = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews")
            legacy.revision += 1
            legacy.updatedAt = date(13)
            restored.upsert(legacy)

            XCTAssertEqual(restored.latestReview?.id, child.id)
            XCTAssertEqual(restored.reviews(on: date(12), calendar: calendar).map(\.id), [child.id])
            XCTAssertTrue(restored.previousReviews(before: date(12), calendar: calendar).isEmpty)
        }
    }

    func testCalendarDayUsesDaylightSavingBoundaryInsteadOfFixed24Hours() throws {
        try withStore { store, _ in
            var local = calendar
            local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
            let start = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 3, day: 8)))
            let next = try XCTUnwrap(local.date(byAdding: .day, value: 1, to: start))
            XCTAssertEqual(next.timeIntervalSince(start), 23 * 3_600)
            let first = SmokingEvent(timestamp: start.addingTimeInterval(60), source: .automatic)
            let second = SmokingEvent(timestamp: next.addingTimeInterval(60), source: .automatic)
            let reviews = store.recordDaily(events: [first, second], origin: .watchHistory,
                windowStart: start, windowEnd: next.addingTimeInterval(600), calendar: local)

            XCTAssertEqual(reviews.count, 2)
            XCTAssertLessThan(try XCTUnwrap(reviews.first).windowEnd, next)
            XCTAssertEqual(reviews.last?.dayStart, next)
        }
    }
}
