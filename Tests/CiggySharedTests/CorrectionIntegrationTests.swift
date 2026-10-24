import Foundation
import XCTest
@testable import CiggyShared

/// Separate replica stores and real snapshot files exercise replay between durable stages.
/// No WatchConnectivity singleton or simulator delivery is needed for these permutations.
@MainActor
final class CorrectionIntegrationTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000.1234567)
    private let lowOperation = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let highOperation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    func testCompetingReductionAndIncreaseConvergeAfterReorderDuplicateAndDiskReload() throws {
        let base = review(originals: originals(count: 3))
        for winnerCount in [1, 5] {
            let loser = decision(base, count: winnerCount == 1 ? 5 : 1, operation: lowOperation)
            let winner = decision(base, count: winnerCount, operation: highOperation)
            var expected: [SmokingEvent]?
            for deliveries in [[loser, winner], [winner, loser], [loser, winner, loser, winner]] {
                try withReplica { replica in
                    replica.store.upsert(base)
                    for item in deliveries { replica.store.upsert(item) }
                    XCTAssertEqual(replica.repository.events.count, winnerCount)
                    XCTAssertEqual(replica.store.reviews.first { $0.id == base.id }?.correction, winner.correction)
                    if let expected { XCTAssertEqual(replica.repository.events, expected) }
                    else { expected = replica.repository.events }

                    try replica.reloadFromDisk()
                    XCTAssertEqual(replica.repository.events, expected)
                    for item in deliveries.reversed() { replica.store.upsert(item) }
                    XCTAssertEqual(replica.repository.events, expected)
                }
            }
        }
    }

    func testSavedDecisionRecoversWhenProcessStopsBeforeApplyingItsEffects() throws {
        try withReplica(configure: false) { replica in
            let base = review(originals: originals(count: 3))
            for event in base.eventSnapshots { replica.repository.addEvent(event) }
            replica.store.upsert(base)
            let saved = try XCTUnwrap(replica.store.markAdjusted(reviewID: base.id, correctedCount: 1, at: instant))
            XCTAssertEqual(replica.repository.events.count, 3, "No effect handler has run yet.")

            // Remove every legacy preference: recovery must come from the atomic files.
            try replica.reloadFromDisk()
            XCTAssertEqual(replica.repository.events.count, 1)
            XCTAssertTrue(replica.outbound.contains { $0.correction == saved.correction })
            XCTAssertTrue(replica.store.pendingTransmissions.isEmpty)
            let recovered = replica.repository.events
            try replica.reloadFromDisk()
            XCTAssertEqual(replica.repository.events, recovered)
        }
    }

    func testEffectsSurviveFailedEnqueueAndRetryUsesTheSameCorrection() throws {
        try withReplica { replica in
            let base = review(originals: originals(count: 2))
            replica.store.upsert(base)
            replica.enqueueSucceeds = false
            XCTAssertFalse(DetectionReviewWorkflow.adjust(base, to: 4, repository: replica.repository, store: replica.store))
            let saved = try XCTUnwrap(replica.store.reviews.first { $0.id == base.id })
            XCTAssertEqual(replica.repository.events.count, 4)
            XCTAssertNotNil(replica.store.lastPersistenceError)
            XCTAssertFalse(replica.store.pendingTransmissions.isEmpty)

            replica.enqueueSucceeds = true
            try replica.reloadFromDisk()
            XCTAssertEqual(replica.repository.events.count, 4)
            XCTAssertTrue(replica.outbound.contains { $0.correction == saved.correction })
            XCTAssertTrue(replica.store.pendingTransmissions.isEmpty)
            XCTAssertTrue(DetectionReviewWorkflow.adjust(base, to: 4, repository: replica.repository, store: replica.store))
            XCTAssertEqual(replica.store.reviews.first { $0.id == base.id }?.correction, saved.correction)
            XCTAssertEqual(replica.repository.events.count, 4)
        }
    }

    func testLateOriginalAndExplicitDeleteCannotUndoTheCanonicalCorrection() throws {
        try withReplica { replica in
            let base = review(originals: originals(count: 1))
            let original = try XCTUnwrap(base.eventSnapshots.first)
            replica.store.upsert(decision(base, count: 0, operation: lowOperation))
            XCTAssertTrue(replica.repository.events.isEmpty)
            XCTAssertFalse(replica.repository.addEvent(original))
            replica.repository.removeEvent(id: original.id)

            replica.store.upsert(decision(base, count: 2, operation: highOperation))
            XCTAssertEqual(replica.repository.events.count, 1, "The winning increase must respect an explicit deletion.")
            let addedID = base.correctionEventID(at: 0)
            XCTAssertEqual(replica.repository.events.first?.id, addedID)
            replica.repository.removeEvent(id: addedID)
            try replica.reloadFromDisk()
            XCTAssertTrue(replica.repository.events.isEmpty)
            replica.store.upsert(decision(base, count: 2, operation: highOperation))
            XCTAssertFalse(replica.repository.addEvent(original))
            XCTAssertTrue(replica.repository.events.isEmpty)
        }
    }

    func testPendingReviewSnapshotsCannotReintroduceAnAliasedAutomaticSession() throws {
        try withReplica { replica in
            let first = SmokingEvent(timestamp: instant, source: .automatic,
                motionSessionStartedAt: instant.addingTimeInterval(-60))
            let alias = SmokingEvent(timestamp: instant.addingTimeInterval(10), source: .automatic,
                motionSessionStartedAt: instant.addingTimeInterval(-50))
            XCTAssertTrue(replica.repository.addEvent(first))
            XCTAssertFalse(replica.repository.addEvent(alias))
            let pending = review(originals: [alias])
            replica.store.upsert(pending)
            XCTAssertEqual(replica.repository.events.count, 1, "A snapshot must use the same deduplication as event delivery.")
            replica.store.upsert(decision(pending, count: 0, operation: highOperation))
            XCTAssertTrue(replica.repository.events.isEmpty, "Correcting an alias corrects its retained original session.")
            try replica.reloadFromDisk()
            XCTAssertTrue(replica.repository.events.isEmpty)
            XCTAssertFalse(replica.repository.addEvent(first))
            XCTAssertFalse(replica.repository.addEvent(alias))
        }
    }

    func testDeletionBeforeAliasDiscoveryStillDeletesTheRetainedSession() throws {
        let first = SmokingEvent(timestamp: instant, source: .automatic,
            motionSessionStartedAt: instant.addingTimeInterval(-60))
        let alias = SmokingEvent(timestamp: instant.addingTimeInterval(10), source: .automatic,
            motionSessionStartedAt: instant.addingTimeInterval(-50))
        for snapshotFirst in [false, true] {
            try withReplica { replica in
                replica.repository.addEvent(first)
                if snapshotFirst { replica.store.upsert(review(originals: [alias])) }
                XCTAssertTrue(replica.repository.receiveDeletion(id: alias.id))
                XCTAssertTrue(replica.repository.receiveEvent(alias))
                replica.store.upsert(review(originals: [alias]))
                XCTAssertTrue(replica.repository.events.isEmpty)
                try replica.reloadFromDisk()
                XCTAssertTrue(replica.repository.events.isEmpty)
            }
        }
    }

    func testExpandedWinningParentRebasesReviewedContinuationWithoutLosingIndependentEvents() throws {
        let events = originals(count: 3)
        let base = review(originals: [events[0]])
        let narrow = decision(base, count: 0, operation: lowOperation)
        var pending = base
        pending.eventIDs = Array(events.prefix(2)).map(\.id)
        pending.eventSnapshots = Array(events.prefix(2))
        pending.windowEnd = events[1].timestamp
        pending.revision = 3
        pending.updatedAt = instant.addingTimeInterval(1)
        var childDecision: DetectionReview?
        try withReplica { source in
            source.store.upsert(narrow)
            source.store.upsert(pending)
            var child = try XCTUnwrap(source.store.reviews.first { $0.id != base.id })
            child.eventIDs.append(events[2].id)
            child.eventSnapshots.append(events[2])
            child.windowEnd = events[2].timestamp
            child.revision += 1
            childDecision = decision(child, count: 1, operation: highOperation)
        }
        let child = try XCTUnwrap(childDecision)
        let broad = decision(pending, count: 2, operation: highOperation)
        for delivery in [[narrow, pending, child, broad], [broad, child, pending, narrow], [child, narrow, broad, pending]] {
            try withReplica { replica in
                delivery.forEach { replica.store.upsert($0) }
                XCTAssertEqual(Set(replica.repository.events.map(\.id)), Set(events.prefix(2).map(\.id)))
                let effectiveChild = try XCTUnwrap(replica.store.reviews(on: instant).first { $0.id == child.id })
                XCTAssertEqual(effectiveChild.eventIDs, [events[2].id])
                XCTAssertEqual(effectiveChild.displayCount, 0, "The independent rejected event stays rejected after its sibling moves to the parent.")
                try replica.reloadFromDisk()
                XCTAssertEqual(Set(replica.repository.events.map(\.id)), Set(events.prefix(2).map(\.id)))
            }
        }
    }

    func testFailedEventSnapshotWriteLeavesJournalRecoverableBeforeAnyReceipt() throws {
        let suite = "CiggyCorrectionFailedEffect.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let eventURL = directory.appendingPathComponent("events.json")
        let reviewURL = directory.appendingPathComponent("reviews.json")
        let original = originals(count: 1)[0]
        let repository = EventRepository(userDefaults: defaults, storageKey: "events", snapshotURL: eventURL)
        XCTAssertTrue(repository.addEvent(original))
        let blocked = EventRepository(userDefaults: defaults, storageKey: "events", snapshotURL: eventURL,
            snapshotWriter: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        let store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews", snapshotURL: reviewURL)
        var delivered: [DetectionReview] = []
        store.configureCorrectionDelivery(repository: blocked) { delivered.append($0); return true }
        let incoming = decision(review(originals: [original]), count: 0, operation: highOperation)
        XCTAssertFalse(store.receive(incoming))
        XCTAssertTrue(delivered.isEmpty, "Do not acknowledge or enqueue a correction before its effect is durable.")
        XCTAssertEqual(blocked.events.map(\.id), [original.id])
        XCTAssertNotNil(store.lastPersistenceError)

        defaults.removePersistentDomain(forName: suite)
        let reopenedRepository = EventRepository(userDefaults: defaults, storageKey: "events", snapshotURL: eventURL)
        let reopenedStore = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews", snapshotURL: reviewURL)
        reopenedStore.configureCorrectionDelivery(repository: reopenedRepository) { delivered.append($0); return true }
        XCTAssertTrue(reopenedRepository.events.isEmpty)
        XCTAssertEqual(delivered.map(\.correction), [incoming.correction])
        XCTAssertTrue(reopenedStore.pendingTransmissions.isEmpty)
    }

    func testFractionalDecisionAndOriginalTimesSurviveISOTransportExactly() throws {
        let original = SmokingEvent(timestamp: instant, source: .automatic,
            motionSessionStartedAt: instant.addingTimeInterval(-17.98765))
        let corrected = decision(review(originals: [original]), count: 3, operation: highOperation)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let received = try decoder.decode(DetectionReview.self, from: encoder.encode(corrected))
        XCTAssertEqual(received, corrected)
        try withReplica { sender in
            try withReplica { receiver in
                sender.store.upsert(corrected)
                receiver.store.upsert(received)
                XCTAssertEqual(sender.repository.events, receiver.repository.events)
                try receiver.reloadFromDisk()
                XCTAssertEqual(sender.repository.events, receiver.repository.events)
            }
        }
    }

    func testLegacyCompletedReviewDoesNotReapplyUnknownHistoricalEffects() throws {
        try withReplica { replica in
            let baseline = originals(count: 3)
            baseline.forEach { replica.repository.addEvent($0) }
            replica.repository.removeEvent(id: baseline[1].id)
            replica.repository.removeEvent(id: baseline[2].id)
            let legacy = DetectionReview(eventIDs: baseline.map(\.id), origin: .watchHistory,
                windowStart: baseline[0].timestamp, windowEnd: baseline[2].timestamp,
                decision: .adjusted, correctedCount: 1, reviewedAt: instant, updatedAt: instant, revision: 2)
            var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            for key in ["correction", "eventSnapshots", "continuationOf", "windowStartReferenceTime", "windowEndReferenceTime",
                        "reviewedAtReferenceTime", "updatedAtReferenceTime", "dayStartReferenceTime"] {
                legacyJSON.removeValue(forKey: key)
            }
            let decoded = try JSONDecoder().decode(DetectionReview.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            XCTAssertNil(decoded.correction)
            replica.store.upsert(decoded)
            try replica.reloadFromDisk()
            XCTAssertEqual(replica.repository.events.map(\.id), [baseline[0].id])
            XCTAssertTrue(replica.store.pendingTransmissions.isEmpty)
        }
    }

    private func originals(count: Int) -> [SmokingEvent] {
        (0..<count).map { index in
            SmokingEvent(timestamp: instant.addingTimeInterval(Double(index) * 300), source: .automatic)
        }
    }

    private func review(originals: [SmokingEvent]) -> DetectionReview {
        DetectionReview(eventIDs: originals.map(\.id), origin: .watchHistory,
            windowStart: originals.first?.timestamp ?? instant, windowEnd: originals.last?.timestamp ?? instant,
            updatedAt: instant, dayStart: Calendar.current.startOfDay(for: instant), eventSnapshots: originals)
    }

    private func decision(_ base: DetectionReview, count: Int, operation: UUID) -> DetectionReview {
        var result = base
        result.decision = .adjusted
        result.correctedCount = count
        result.reviewedAt = instant
        result.updatedAt = instant
        result.revision += 1
        result.correction = .init(operationID: operation, decidedAt: instant)
        return result
    }

    private func withReplica(configure: Bool = true, _ body: (Replica) throws -> Void) throws {
        let replica = try Replica()
        defer { replica.cleanup() }
        if configure { replica.configure() }
        try body(replica)
    }

    @MainActor
    private final class Replica {
        let suite = "CiggyCorrectionIntegration.\(UUID().uuidString)"
        let directory: URL
        let defaults: UserDefaults
        var repository: EventRepository
        var store: DetectionReviewStore
        var outbound: [DetectionReview] = []
        var enqueueSucceeds = true

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: suite)!
            repository = EventRepository(userDefaults: defaults, storageKey: "events",
                snapshotURL: directory.appendingPathComponent("events.json"))
            store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews",
                snapshotURL: directory.appendingPathComponent("reviews.json"))
        }

        func configure() {
            store.configureCorrectionDelivery(repository: repository) { [weak self] review in
                guard let self, self.enqueueSucceeds else { return false }
                self.outbound.append(review)
                return true
            }
        }

        func reloadFromDisk() throws {
            defaults.removePersistentDomain(forName: suite)
            repository = EventRepository(userDefaults: defaults, storageKey: "events",
                snapshotURL: directory.appendingPathComponent("events.json"))
            store = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews",
                snapshotURL: directory.appendingPathComponent("reviews.json"))
            configure()
            XCTAssertNil(repository.lastPersistenceError)
            XCTAssertNil(store.lastPersistenceError)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
