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
