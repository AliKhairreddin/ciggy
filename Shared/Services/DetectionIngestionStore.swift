import Foundation

/// Write-ahead journal for automatic detections. A crash after saving the event,
/// review, or outbox is repaired before the job is retired or history advances.
@MainActor
public final class DetectionIngestionStore {
    private struct Job: Codable {
        let id: UUID
        let events: [SmokingEvent]
        let origin: DetectionReviewOrigin
        let windowStart: Date
        let windowEnd: Date
        let createdAt: Date
    }
    private var jobs: [Job] = []
    private let snapshot: DurableSnapshotFile
    private var loadFailed = false
    public private(set) var lastPersistenceError: String?
    public var pendingCount: Int { jobs.count }

    public init(snapshotURL: URL = DurableSnapshotFile.defaultURL(name: "DetectionIngestion.jobs.v1")) {
        snapshot = DurableSnapshotFile(url: snapshotURL)
        do {
            if let data = try snapshot.load() { jobs = try JSONDecoder().decode([Job].self, from: data) }
        } catch {
            loadFailed = true
            lastPersistenceError = "Could not read unfinished detections. \(error.localizedDescription)"
        }
    }

    /// Nil means retry is required. A non-nil result permits the history checkpoint
    /// to advance, including an empty batch or an already-recorded session.
    public func ingest(
        _ candidates: [DetectionCandidate], origin: DetectionReviewOrigin,
        windowStart: Date, windowEnd: Date,
        repository: EventRepository, reviews: DetectionReviewStore,
        sendEvent: (SmokingEvent) -> Bool, sendReview: (DetectionReview) -> Bool
    ) -> [DetectionReview]? {
        guard loadFailed == false else { return nil }
        if candidates.isEmpty == false {
            let events = candidates.map { $0.detectedEvent() }
            let id = DetectionReview.stableID("ingestion:\(origin.rawValue):" + events.map { $0.id.uuidString }.sorted().joined(separator: ":"))
            if jobs.contains(where: { $0.id == id }) == false {
                let start = candidates.reduce(windowStart) { min($0, $1.motionSessionStartedAt ?? $1.gestureAt) }
                let end = candidates.reduce(windowEnd) { max($0, $1.gestureAt) }
                let job = Job(id: id, events: events, origin: origin, windowStart: start, windowEnd: end, createdAt: Date())
                guard save(jobs + [job]) else { return nil }
            }
        }
        return recover(repository: repository, reviews: reviews, sendEvent: sendEvent, sendReview: sendReview)
    }

    @discardableResult public func recover(
        repository: EventRepository, reviews: DetectionReviewStore,
        sendEvent: (SmokingEvent) -> Bool, sendReview: (DetectionReview) -> Bool
    ) -> [DetectionReview]? {
        guard loadFailed == false else { return nil }
        var changed: [DetectionReview] = []
        for job in jobs {
            for event in job.events {
                guard repository.receiveEvent(event) else {
                    lastPersistenceError = repository.lastPersistenceError ?? "Could not save a detection."
                    return nil
                }
            }
            // Exact originals exclude alternate IDs for an already-counted session.
            // Hidden originals still exist, so a user correction is never undone.
            let originals = repository.originalEvents(for: job.events.map(\.id))
            let covered = Set(reviews.reviews.flatMap(\.eventIDs))
            let unreviewed = originals.filter { covered.contains($0.id) == false }
            if unreviewed.isEmpty == false {
                changed += reviews.recordDaily(events: unreviewed, origin: job.origin,
                    windowStart: job.windowStart, windowEnd: job.windowEnd, at: job.createdAt)
                guard reviews.lastPersistenceError == nil else {
                    lastPersistenceError = reviews.lastPersistenceError
                    return nil
                }
            }
            let ids = Set(originals.map(\.id))
            let related = reviews.reviews.filter { Set($0.eventIDs).isDisjoint(with: ids) == false }
            for event in originals {
                guard sendEvent(event) else { lastPersistenceError = "Detection saved; companion sync will retry."; return nil }
            }
            for review in related {
                guard sendReview(review) else { lastPersistenceError = "Review saved; companion sync will retry."; return nil }
            }
            guard save(jobs.filter { $0.id != job.id }) else { return nil }
        }
        lastPersistenceError = nil
        return changed
    }

    private func save(_ next: [Job]) -> Bool {
        do {
            try snapshot.write(JSONEncoder().encode(next))
            jobs = next
            lastPersistenceError = nil
            return true
        } catch {
            lastPersistenceError = "Could not save unfinished detections. \(error.localizedDescription)"
            return false
        }
    }
}
