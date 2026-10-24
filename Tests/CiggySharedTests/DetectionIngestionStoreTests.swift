import Foundation
import XCTest
@testable import CiggyShared

@MainActor
final class DetectionIngestionStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testRestartAfterEventOrReviewEnqueueFailureReusesOriginalEventAndReview() throws {
        for failEvent in [true, false] {
            try withContext { context in
                let candidate = candidate()
                var deliveredEvents: [SmokingEvent] = []
                let first = context.ingest([candidate], sendEvent: { event in
                    if failEvent { return false }
                    deliveredEvents.append(event)
                    return true
                }, sendReview: { _ in false })
                XCTAssertNil(first)
                XCTAssertEqual(context.journal.pendingCount, 1)
                XCTAssertEqual(context.repository.events.map(\.id), [candidate.id])
                let review = try XCTUnwrap(context.reviews.reviews.first)
                XCTAssertEqual(review.eventIDs, [candidate.id])

                context.reloadFromDisk()
                var deliveredReviews: [DetectionReview] = []
                XCTAssertNotNil(context.journal.recover(repository: context.repository, reviews: context.reviews,
                    sendEvent: { deliveredEvents.append($0); return true },
                    sendReview: { deliveredReviews.append($0); return true }))
                XCTAssertEqual(context.journal.pendingCount, 0)
                XCTAssertEqual(context.repository.events.map(\.id), [candidate.id])
                XCTAssertEqual(context.reviews.reviews.map(\.id), [review.id])
                XCTAssertTrue(deliveredEvents.allSatisfy { $0.id == candidate.id })
                XCTAssertEqual(deliveredReviews.map(\.id), [review.id])
                context.reloadFromDisk()
                XCTAssertEqual(context.journal.pendingCount, 0)
            }
        }
    }

    func testJournalRecoversWhenEventPersistenceFailsBeforeAnyEventExists() throws {
        try withContext { context in
            let blocked = EventRepository(userDefaults: context.defaults, storageKey: "events", snapshotURL: context.eventsURL,
                snapshotWriter: { _ in throw CocoaError(.fileWriteOutOfSpace) })
            let candidate = candidate()
            var transmissions = 0
            XCTAssertNil(context.journal.ingest([candidate], origin: .watchHistory,
                windowStart: start, windowEnd: candidate.gestureAt, repository: blocked, reviews: context.reviews,
                sendEvent: { _ in transmissions += 1; return true }, sendReview: { _ in transmissions += 1; return true }))
            XCTAssertEqual(transmissions, 0)
            XCTAssertTrue(blocked.events.isEmpty)
            XCTAssertEqual(context.journal.pendingCount, 1)

            context.reloadFromDisk()
            XCTAssertNotNil(context.journal.recover(repository: context.repository, reviews: context.reviews,
                sendEvent: { _ in true }, sendReview: { _ in true }))
            XCTAssertEqual(context.repository.events.map(\.id), [candidate.id])
            XCTAssertEqual(context.reviews.reviews.flatMap(\.eventIDs), [candidate.id])
            XCTAssertEqual(context.journal.pendingCount, 0)
        }
    }

    func testJournalRecoversAfterEventCommitButBeforeReviewCommit() throws {
        try withContext { context in
            let blocked = DetectionReviewStore(userDefaults: context.defaults, storageKey: "reviews", snapshotURL: context.reviewsURL,
                snapshotWriter: { _ in throw CocoaError(.fileWriteOutOfSpace) })
            blocked.configureCorrectionDelivery(repository: context.repository, enqueue: { _ in true })
            let candidate = candidate()
            XCTAssertNil(context.journal.ingest([candidate], origin: .watchHistory,
                windowStart: start, windowEnd: candidate.gestureAt, repository: context.repository, reviews: blocked,
                sendEvent: { _ in true }, sendReview: { _ in true }))
            XCTAssertEqual(context.repository.events.map(\.id), [candidate.id])
            XCTAssertTrue(blocked.reviews.isEmpty)
            XCTAssertEqual(context.journal.pendingCount, 1)

            context.reloadFromDisk()
            XCTAssertNotNil(context.journal.recover(repository: context.repository, reviews: context.reviews,
                sendEvent: { _ in true }, sendReview: { _ in true }))
            XCTAssertEqual(context.repository.events.map(\.id), [candidate.id])
            XCTAssertEqual(context.reviews.reviews.flatMap(\.eventIDs), [candidate.id])
            XCTAssertEqual(context.journal.pendingCount, 0)
        }
    }

    func testRecoveryDoesNotReopenOrResurrectAnAlreadyCorrectedDetection() throws {
        try withContext { context in
            let candidate = candidate()
            XCTAssertNil(context.ingest([candidate], sendEvent: { _ in true }, sendReview: { _ in false }))
            let review = try XCTUnwrap(context.reviews.reviews.first)
            XCTAssertTrue(DetectionReviewWorkflow.adjust(review, to: 0, repository: context.repository, store: context.reviews))
            XCTAssertTrue(context.repository.events.isEmpty)
            let correction = context.reviews.reviews.first?.correction

            context.reloadFromDisk()
            var delivered: [DetectionReview] = []
            XCTAssertNotNil(context.journal.recover(repository: context.repository, reviews: context.reviews,
                sendEvent: { _ in true }, sendReview: { delivered.append($0); return true }))
            XCTAssertTrue(context.repository.events.isEmpty)
            XCTAssertEqual(context.reviews.reviews.count, 1)
            XCTAssertEqual(context.reviews.reviews.first?.correction, correction)
            XCTAssertEqual(delivered.map(\.decision), [.adjusted])
            XCTAssertEqual(context.journal.pendingCount, 0)
        }
    }

    func testAlternateCandidateDoesNotCreateAnotherReviewOrRestoreCorrectedSession() throws {
        try withContext { context in
            let original = candidate()
            XCTAssertNotNil(context.ingest([original]))
            let review = try XCTUnwrap(context.reviews.reviews.first)
            XCTAssertTrue(DetectionReviewWorkflow.adjust(review, to: 0, repository: context.repository, store: context.reviews))
            context.reloadFromDisk()

            let alternate = DetectionCandidate(gestureAt: original.gestureAt.addingTimeInterval(10),
                detectedAt: original.detectedAt.addingTimeInterval(10),
                motionSessionStartedAt: start.addingTimeInterval(5), motionGestureCount: 5)
            var transmissions = 0
            XCTAssertNotNil(context.ingest([alternate], sendEvent: { _ in transmissions += 1; return true },
                sendReview: { _ in transmissions += 1; return true }))
            XCTAssertEqual(transmissions, 0)
            XCTAssertEqual(context.reviews.reviews.map(\.id), [review.id])
            XCTAssertTrue(context.repository.events.isEmpty)
            XCTAssertEqual(context.journal.pendingCount, 0)
        }
    }

    private func candidate() -> DetectionCandidate {
        .init(gestureAt: start.addingTimeInterval(80), detectedAt: start.addingTimeInterval(80),
            motionSessionStartedAt: start, motionGestureCount: 5)
    }

    private func withContext(_ body: (Context) throws -> Void) throws {
        let context = try Context()
        defer { context.cleanup() }
        try body(context)
    }

    @MainActor
    private final class Context {
        let suite = "DetectionIngestionIntegration.\(UUID().uuidString)"
        let directory: URL
        let defaults: UserDefaults
        let eventsURL: URL
        let reviewsURL: URL
        let ingestionURL: URL
        var repository: EventRepository
        var reviews: DetectionReviewStore
        var journal: DetectionIngestionStore

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: suite)!
            eventsURL = directory.appendingPathComponent("events.json")
            reviewsURL = directory.appendingPathComponent("reviews.json")
            ingestionURL = directory.appendingPathComponent("ingestion.json")
            repository = EventRepository(userDefaults: defaults, storageKey: "events", snapshotURL: eventsURL)
            reviews = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews", snapshotURL: reviewsURL)
            journal = DetectionIngestionStore(snapshotURL: ingestionURL)
            reviews.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
        }

        func ingest(_ candidates: [DetectionCandidate], sendEvent: (SmokingEvent) -> Bool = { _ in true },
                    sendReview: (DetectionReview) -> Bool = { _ in true }) -> [DetectionReview]? {
            journal.ingest(candidates, origin: .watchHistory,
                windowStart: candidates.first?.motionSessionStartedAt ?? Date(),
                windowEnd: candidates.last?.gestureAt ?? Date(), repository: repository, reviews: reviews,
                sendEvent: sendEvent, sendReview: sendReview)
        }

        func reloadFromDisk() {
            defaults.removePersistentDomain(forName: suite)
            repository = EventRepository(userDefaults: defaults, storageKey: "events", snapshotURL: eventsURL)
            reviews = DetectionReviewStore(userDefaults: defaults, storageKey: "reviews", snapshotURL: reviewsURL)
            journal = DetectionIngestionStore(snapshotURL: ingestionURL)
            reviews.configureCorrectionDelivery(repository: repository, enqueue: { _ in true })
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
