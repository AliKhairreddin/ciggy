import Foundation
import XCTest
@testable import CiggyShared

@MainActor
final class CorrectionPersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000.456789)

    func testFailedSourceWriteDoesNotPublishOrApplyTheDecision() throws {
        try withFiles { defaults, reviewURL, eventURL in
            var fail = false
            let file = DurableSnapshotFile(url: reviewURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL, snapshotWriter: { data in
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
                try file.write(data)
            })
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            store.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
            let pending = base()
            XCTAssertTrue(store.receive(pending))
            fail = true
            XCTAssertNil(store.markAdjusted(reviewID: pending.id, correctedCount: 0, at: now))
            XCTAssertEqual(store.latestReview?.decision, .pending)
            XCTAssertEqual(repository.events.count, 1)
            XCTAssertNotNil(store.lastPersistenceError)
            let restored = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            XCTAssertEqual(restored.latestReview?.decision, .pending)
            fail = false
            XCTAssertNotNil(store.markAdjusted(reviewID: pending.id, correctedCount: 0, at: now))
            XCTAssertTrue(store.retryPendingCorrections())
            XCTAssertTrue(repository.events.isEmpty)
        }
    }

    func testFailureClearingAlreadyQueuedIntentRecoversWithoutDuplicateAdditions() throws {
        try withFiles { defaults, reviewURL, eventURL in
            var failClear = false
            var armFailure = false
            var sent: [DetectionReview] = []
            let file = DurableSnapshotFile(url: reviewURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL, snapshotWriter: { data in
                if failClear { throw CocoaError(.fileWriteOutOfSpace) }
                try file.write(data)
            })
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            store.configureCorrectionDelivery(repository: repository) { review in
                sent.append(review)
                if armFailure { failClear = true }
                return true
            }
            let pending = base()
            XCTAssertTrue(store.receive(pending))
            armFailure = true
            let decided = try XCTUnwrap(store.markAdjusted(reviewID: pending.id, correctedCount: 3, at: now))
            XCTAssertFalse(store.retryPendingCorrections())
            XCTAssertEqual(repository.events.count, 3)
            XCTAssertTrue(sent.contains { $0.correction == decided.correction })
            XCTAssertFalse(store.pendingTransmissions.isEmpty)
            XCTAssertNotNil(store.lastPersistenceError)
            let before = repository.events

            let restoredRepository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            let restoredStore = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            var replayed: [DetectionReview] = []
            restoredStore.configureCorrectionDelivery(repository: restoredRepository) {
                replayed.append($0)
                return true
            }
            XCTAssertEqual(restoredRepository.events, before)
            XCTAssertTrue(replayed.contains { $0.correction == decided.correction })
            XCTAssertTrue(restoredStore.pendingTransmissions.isEmpty)
            XCTAssertNil(restoredStore.lastPersistenceError)
        }
    }

    func testMalformedCorrectionIsRejectedBeforeTheJournalIsPoisoned() throws {
        try withFiles { defaults, reviewURL, eventURL in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            store.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
            let pending = base()
            XCTAssertTrue(store.receive(pending))
            var invalid = pending
            invalid.decision = .adjusted
            invalid.correctedCount = -1
            invalid.correction = .init(decidedAt: now)
            XCTAssertFalse(store.receive(invalid))
            XCTAssertEqual(store.latestReview?.decision, .pending)
            invalid.correctedCount = 0
            invalid.eventSnapshots = [SmokingEvent(id: pending.eventIDs[0], timestamp: Date(timeIntervalSince1970: 1e100), source: .automatic)]
            XCTAssertFalse(store.receive(invalid))
            XCTAssertEqual(DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL).latestReview?.decision, .pending)
        }
    }

    func testUnreadableJournalIsPreservedAndCannotBeAcknowledged() throws {
        try withFiles { defaults, reviewURL, eventURL in
            let original = Data("unreadable saved journal".utf8)
            try original.write(to: reviewURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            var deliveries = 0
            store.configureCorrectionDelivery(repository: repository) { _ in deliveries += 1; return true }
            XCTAssertFalse(store.receive(base()))
            XCTAssertFalse(store.retryPendingCorrections())
            XCTAssertNotNil(store.lastPersistenceError)
            XCTAssertEqual(try Data(contentsOf: reviewURL), original)
            XCTAssertEqual(deliveries, 0)
        }
    }

    func testAccurateDecisionCanRestoreACompetingReduction() throws {
        try withFiles { defaults, reviewURL, eventURL in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            store.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
            let pending = base()
            var reduced = pending
            reduced.decision = .adjusted
            reduced.correctedCount = 0
            reduced.revision = 2
            reduced.correction = .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, decidedAt: now)
            var accurate = reduced
            accurate.decision = .accurate
            accurate.correctedCount = nil
            accurate.correction = .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, decidedAt: now)
            XCTAssertTrue(store.receive(reduced))
            XCTAssertTrue(repository.events.isEmpty)
            XCTAssertTrue(store.receive(accurate))
            XCTAssertEqual(repository.events, pending.eventSnapshots)
            XCTAssertTrue(store.receive(reduced))
            XCTAssertEqual(repository.events, pending.eventSnapshots)
        }
    }

    func testUnreadableLegacyEventDefaultsCannotBeOverwritten() throws {
        try withFiles { defaults, _, eventURL in
            let bytes = Data("unreadable previous event history".utf8)
            defaults.set(bytes, forKey: "EventRepository.events.v1")
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            XCTAssertFalse(repository.receiveEvent(SmokingEvent(timestamp: now, source: .manual)))
            XCTAssertFalse(repository.receiveDeletion(id: UUID()))
            XCTAssertNotNil(repository.lastPersistenceError)
            XCTAssertEqual(defaults.data(forKey: "EventRepository.events.v1"), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: eventURL.path))
        }
    }

    func testOverlappingReviewScopesHaveOnePreferredOwnerInEitherDeliveryOrder() throws {
        let events = (0..<3).map { SmokingEvent(timestamp: now.addingTimeInterval(Double($0) * 300), source: .automatic) }
        var first = DetectionReview(eventIDs: Array(events.prefix(2)).map(\.id), origin: .watchHistory,
            windowStart: events[0].timestamp, windowEnd: events[1].timestamp, decision: .adjusted,
            correctedCount: 0, updatedAt: now, revision: 2, dayStart: Calendar.current.startOfDay(for: now),
            eventSnapshots: Array(events.prefix(2)),
            correction: .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, decidedAt: now))
        let second = DetectionReview(eventIDs: Array(events.suffix(2)).map(\.id), origin: .liveWatch,
            windowStart: events[1].timestamp, windowEnd: events[2].timestamp, decision: .accurate,
            updatedAt: now, revision: 2, dayStart: first.dayStart, eventSnapshots: Array(events.suffix(2)),
            correction: .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, decidedAt: now))
        for delivery in [[first, second], [second, first]] {
            try withFiles { defaults, reviewURL, eventURL in
                let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
                let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
                store.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
                for review in delivery { XCTAssertTrue(store.receive(review)) }
                XCTAssertEqual(repository.events, Array(events.suffix(2)))
                XCTAssertEqual(store.reviews(on: now).first { $0.id == first.id }?.eventIDs, [events[0].id])
                for review in delivery.reversed() { XCTAssertTrue(store.receive(review)) }
                XCTAssertEqual(repository.events, Array(events.suffix(2)))
            }
        }
        // Fully overlapping losing additions must disappear with their superseded scope.
        first.eventIDs = second.eventIDs
        first.eventSnapshots = second.eventSnapshots
        first.correctedCount = 4
        XCTAssertEqual(DetectionReview.effectiveScopes([first, second]).map(\.id), [second.id])
    }

    func testDifferentFirstAutomaticRepresentativesAgreeOnCorrectedCount() throws {
        let first = SmokingEvent(timestamp: now, source: .automatic, motionSessionStartedAt: now.addingTimeInterval(-60))
        let alias = SmokingEvent(timestamp: now.addingTimeInterval(10), source: .automatic,
            motionSessionStartedAt: now.addingTimeInterval(-50))
        let pending = DetectionReview(eventIDs: [alias.id], origin: .watchHistory,
            windowStart: alias.timestamp, windowEnd: alias.timestamp, updatedAt: now,
            dayStart: Calendar.current.startOfDay(for: now), eventSnapshots: [alias])
        var reduction = pending
        reduction.decision = .adjusted
        reduction.correctedCount = 0
        reduction.revision = 2
        reduction.correction = .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, decidedAt: now)
        var increase = reduction
        increase.correctedCount = 2
        increase.correction = .init(operationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, decidedAt: now)
        for originals in [[first, alias], [alias, first]] {
            for decisions in [[reduction, increase], [increase, reduction]] {
                try withFiles { defaults, reviewURL, eventURL in
                    let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
                    let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
                    originals.forEach { _ = repository.receiveEvent($0) }
                    store.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
                    for review in decisions { XCTAssertTrue(store.receive(review)) }
                    XCTAssertEqual(repository.events.count, 2)
                    XCTAssertEqual(store.latestReview?.correction, increase.correction)
                    XCTAssertEqual(repository.events.filter { $0.source == .manual }.map(\.id), [pending.correctionEventID(at: 0)])
                }
            }
        }
    }

    func testEquivalentPendingOrdersReachQuiescenceInsteadOfEchoingForever() throws {
        try withFiles { firstDefaults, firstURL, firstEventURL in
            try withFiles { secondDefaults, secondURL, secondEventURL in
                let firstRepo = EventRepository(userDefaults: firstDefaults, snapshotURL: firstEventURL)
                let secondRepo = EventRepository(userDefaults: secondDefaults, snapshotURL: secondEventURL)
                let firstStore = DetectionReviewStore(userDefaults: firstDefaults, snapshotURL: firstURL)
                let secondStore = DetectionReviewStore(userDefaults: secondDefaults, snapshotURL: secondURL)
                var firstOutgoing: [DetectionReview] = []
                var secondOutgoing: [DetectionReview] = []
                firstStore.configureCorrectionDelivery(repository: firstRepo) { firstOutgoing.append($0); return true }
                secondStore.configureCorrectionDelivery(repository: secondRepo) { secondOutgoing.append($0); return true }
                var first = base()
                let extra = SmokingEvent(timestamp: now.addingTimeInterval(300), source: .automatic)
                first.eventIDs.append(extra.id)
                first.eventSnapshots.append(extra)
                var second = first
                second.eventIDs.reverse()
                XCTAssertTrue(firstStore.receive(first))
                XCTAssertTrue(secondStore.receive(second))
                for _ in 0..<20 {
                    if firstOutgoing.isEmpty && secondOutgoing.isEmpty { break }
                    if firstOutgoing.isEmpty == false { XCTAssertTrue(secondStore.receive(firstOutgoing.removeFirst())) }
                    if secondOutgoing.isEmpty == false { XCTAssertTrue(firstStore.receive(secondOutgoing.removeFirst())) }
                }
                XCTAssertTrue(firstOutgoing.isEmpty)
                XCTAssertTrue(secondOutgoing.isEmpty)
                XCTAssertEqual(firstStore.reviews, secondStore.reviews)
                XCTAssertTrue(firstStore.pendingTransmissions.isEmpty)
                XCTAssertTrue(secondStore.pendingTransmissions.isEmpty)
            }
        }
    }

    func testMissingLegacyOriginalKeepsCorrectionPendingUntilEventArrives() throws {
        try withFiles { defaults, reviewURL, eventURL in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: eventURL)
            let store = DetectionReviewStore(userDefaults: defaults, snapshotURL: reviewURL)
            var sent: [DetectionReview] = []
            store.configureCorrectionDelivery(repository: repository) { sent.append($0); return true }
            var corrected = base()
            let original = try XCTUnwrap(corrected.eventSnapshots.first)
            corrected.eventSnapshots = []
            corrected.decision = .adjusted
            corrected.correctedCount = 2
            corrected.correction = .init(decidedAt: now)
            XCTAssertFalse(store.receive(corrected))
            XCTAssertTrue(repository.events.isEmpty)
            XCTAssertNotNil(store.lastPersistenceError)
            XCTAssertTrue(sent.isEmpty)
            XCTAssertFalse(store.pendingTransmissions.isEmpty)
            XCTAssertTrue(repository.receiveEvent(original))
            XCTAssertTrue(store.retryPendingCorrections())
            XCTAssertEqual(repository.events.count, 2)
            XCTAssertEqual(sent.last?.correction, corrected.correction)
            XCTAssertNil(store.lastPersistenceError)
        }
    }

    private func base() -> DetectionReview {
        let event = SmokingEvent(timestamp: now, source: .automatic)
        return DetectionReview(eventIDs: [event.id], origin: .watchHistory,
            windowStart: now, windowEnd: now, updatedAt: now,
            dayStart: Calendar.current.startOfDay(for: now), eventSnapshots: [event])
    }

    private func withFiles(_ body: (UserDefaults, URL, URL) throws -> Void) throws {
        let suite = "CorrectionPersistenceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(defaults, directory.appendingPathComponent("reviews.json"), directory.appendingPathComponent("events.json"))
    }
}
