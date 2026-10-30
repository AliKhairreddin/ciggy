import Combine
import CryptoKit
import Foundation

/// Persists and merges the passive detection summaries shown on iPhone and Apple Watch.
@MainActor
public final class DetectionReviewStore: ObservableObject {
	@Published public private(set) var reviews: [DetectionReview] = []

	public var latestReview: DetectionReview? {
		activeReviews.max { $0.updatedAt < $1.updatedAt }
	}

	/// Replaced legacy summaries remain saved for audit and delayed sync, but do
	/// not compete with their day-scoped replacements in the interface.
	private var activeReviews: [DetectionReview] {
		let replaced = Set(reviews.compactMap(\.parentReviewID))
		return DetectionReview.effectiveScopes(reviews, resolvingEventID: { self.correctionRepository?.canonicalEventID($0) ?? $0 })
            .filter { replaced.contains($0.id) == false }
	}

	public func reviews(on day: Date, calendar: Calendar = .current) -> [DetectionReview] {
		activeReviews.filter { review in
			if let dayStart = review.dayStart { return calendar.isDate(dayStart, inSameDayAs: day) }
			return calendar.isDate(review.windowStart, inSameDayAs: day) &&
				calendar.isDate(review.windowEnd, inSameDayAs: day)
		}.sorted { $0.updatedAt > $1.updatedAt }
	}

	public func latestReview(on day: Date, calendar: Calendar = .current) -> DetectionReview? {
		reviews(on: day, calendar: calendar).first
	}

	public func previousReviews(before day: Date, calendar: Calendar = .current) -> [DetectionReview] {
		let today = calendar.startOfDay(for: day)
		return activeReviews.filter { $0.windowStart < today }
			.sorted { $0.windowEnd > $1.windowEnd }
	}

    @Published public private(set) var lastPersistenceError: String?
    public var pendingTransmissions: [DetectionReview] {
        reviews.filter { pendingTransmissionIDs.contains($0.id) }
    }
    private struct Snapshot: Codable {
        var reviews: [DetectionReview]
        var pendingTransmissionIDs: Set<UUID>
    }
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let snapshotFile: DurableSnapshotFile?
    private let snapshotWriter: ((Data) throws -> Void)?
    private var pendingTransmissionIDs = Set<UUID>()
    private var loadFailed = false
    private weak var correctionRepository: EventRepository?
    private var enqueueReview: ((DetectionReview) -> Bool)?
    private var isRetrying = false

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "DetectionReviewStore.reviews.v1",
        snapshotURL: URL? = nil,
        snapshotWriter: ((Data) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.snapshotFile = (snapshotURL ?? (userDefaults === UserDefaults.standard ?
            DurableSnapshotFile.defaultURL(name: storageKey) : nil)).map { DurableSnapshotFile(url: $0) }
        self.snapshotWriter = snapshotWriter
        load()
    }

    /// Bind before draining the incoming transport. The review journal is the
    /// source of truth; effects and outgoing delivery can always be retried.
    public func configureCorrectionDelivery(repository: EventRepository, enqueue: @escaping (DetectionReview) -> Bool) {
        correctionRepository = repository
        enqueueReview = enqueue
        _ = retryPendingCorrections()
    }

    @discardableResult
    public func retryPendingCorrections() -> Bool {
        guard loadFailed == false else { return false }
        guard isRetrying == false else { return false }
        guard let repository = correctionRepository else {
            lastPersistenceError = "The cigarette log is not ready to save this review. Please try again."
            return false
        }
        isRetrying = true
        defer { isRetrying = false }
        guard repository.applyCorrections(reviews) else {
            lastPersistenceError = repository.lastPersistenceError ?? "Could not apply the saved review. Please retry."
            return false
        }
        for review in pendingTransmissions {
            guard enqueueReview?(review) == true else {
                lastPersistenceError = "The review is saved locally. Its sync queue could not be saved; please retry."
                return false
            }
            var remaining = pendingTransmissionIDs
            remaining.remove(review.id)
            guard persist(reviews, pending: remaining) else { return false }
        }
        lastPersistenceError = nil
        return true
    }

	/// Compatibility convenience for callers recording events from a single day.
	@discardableResult
	public func record(
		events: [SmokingEvent],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		at updatedAt: Date = Date(),
		mergeWithPending: Bool = true
	) -> DetectionReview? {
		recordDaily(events: events, origin: origin, windowStart: windowStart,
		            windowEnd: windowEnd, at: updatedAt, mergeWithPending: mergeWithPending).last
	}

	/// Partition by event day before merging. An old backlog can never turn today's
	/// review into a multi-day count or change the date of a saved cigarette.
	@discardableResult
	public func recordDaily(
		events: [SmokingEvent],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		at updatedAt: Date = Date(),
		mergeWithPending: Bool = true,
		calendar: Calendar = .current
	) -> [DetectionReview] {
		guard [windowStart, windowEnd, updatedAt].allSatisfy({
			$0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
		}) else { return [] }
        var nextReviews = reviews
		let validEvents = events.filter { $0.timestamp.timeIntervalSince1970.isFinite &&
			$0.timestamp >= .distantPast && $0.timestamp <= .distantFuture }
		let grouped = Dictionary(grouping: validEvents) { calendar.startOfDay(for: $0.timestamp) }
		let replacedIDs = Set(nextReviews.compactMap(\.parentReviewID))
		var result: [DetectionReview] = []
		for day in grouped.keys.sorted() {
			guard let dailyEvents = grouped[day]?.sorted(by: { $0.timestamp < $1.timestamp }),
			      let first = dailyEvents.first, let last = dailyEvents.last,
			      let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
			let start = min(first.timestamp, max(day, min(windowStart, windowEnd)))
			let end = max(last.timestamp, min(nextDay.addingTimeInterval(-0.001), max(windowStart, windowEnd)))
			let ids = dailyEvents.map(\.id)
			if mergeWithPending, let index = nextReviews.lastIndex(where: {
				$0.decision == .pending && $0.origin == origin && $0.dayStart == day &&
				replacedIDs.contains($0.id) == false
			}) {
				var review = nextReviews[index]
				var seen = Set(review.eventIDs)
				review.eventIDs.append(contentsOf: ids.filter { seen.insert($0).inserted })
                review.eventSnapshots = Self.mergeSnapshots(review.eventSnapshots, dailyEvents, scope: review.eventIDs)
				review.windowStart = min(review.windowStart, start)
				review.windowEnd = max(review.windowEnd, end)
				review.updatedAt = updatedAt
				if review.revision < Int.max { review.revision += 1 }
				nextReviews[index] = review
				result.append(review)
			} else {
				let review = DetectionReview(eventIDs: ids, origin: origin, windowStart: start,
				                             windowEnd: end, updatedAt: updatedAt, dayStart: day, eventSnapshots: dailyEvents)
				nextReviews.append(review)
				result.append(review)
			}
		}
		if result.isEmpty == false {
            let pending = pendingTransmissionIDs.union(result.map(\.id))
            guard persist(nextReviews, pending: pending) else { return [] }
            if correctionRepository != nil { _ = retryPendingCorrections() }
        }
		return result
	}

	/// Wait for every event before migrating an older summary: review messages can
	/// arrive before their event messages. Both devices derive the same child IDs.
	@discardableResult
	public func normalizePendingReviews(events: [SmokingEvent], calendar: Calendar = .current) -> [DetectionReview] {
		let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		var created: [DetectionReview] = []
        var nextReviews = reviews
		for legacy in activeReviews where legacy.dayStart == nil && legacy.decision == .pending {
			let resolved = legacy.eventIDs.compactMap { byID[$0] }
			guard resolved.count == legacy.eventIDs.count, resolved.isEmpty == false else { continue }
			let grouped = Dictionary(grouping: resolved) { calendar.startOfDay(for: $0.timestamp) }
			for day in grouped.keys.sorted() {
				guard let daily = grouped[day]?.sorted(by: { $0.timestamp < $1.timestamp }),
				      let first = daily.first, let last = daily.last,
				      let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
				let ids = daily.map(\.id)
				let child = DetectionReview(id: Self.dailyID(parent: legacy.id, eventIDs: ids),
				                            eventIDs: ids, origin: legacy.origin,
				                            windowStart: min(first.timestamp, max(day, legacy.windowStart)),
				                            windowEnd: max(last.timestamp, min(nextDay.addingTimeInterval(-0.001), legacy.windowEnd)),
				                            updatedAt: legacy.updatedAt, dayStart: day, parentReviewID: legacy.id, eventSnapshots: daily)
				guard nextReviews.contains(where: { $0.id == child.id }) == false else { continue }
				nextReviews.append(child)
				created.append(child)
			}
		}
		if created.isEmpty == false {
            guard persist(nextReviews, pending: pendingTransmissionIDs.union(created.map(\.id))) else { return [] }
            if correctionRepository != nil { _ = retryPendingCorrections() }
        }
		return created
	}

	private static func dailyID(parent: UUID, eventIDs: [UUID]) -> UUID {
		let key = "ciggy-daily-review-v1:\(parent.uuidString):" + eventIDs.map(\.uuidString).sorted().joined(separator: ":")
		return stableID(for: key)
	}

	private static func stableID(for key: String) -> UUID {
		var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
		bytes[6] = (bytes[6] & 0x0f) | 0x50
		bytes[8] = (bytes[8] & 0x3f) | 0x80
		return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
		                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
	}

	@discardableResult
	public func markAccurate(reviewID: UUID, at date: Date = Date()) -> DetectionReview? {
		updatePending(reviewID: reviewID, decision: .accurate, correctedCount: nil, at: date)
	}

	@discardableResult
	public func markAdjusted(
		reviewID: UUID,
		correctedCount: Int,
		at date: Date = Date()
	) -> DetectionReview? {
		updatePending(
			reviewID: reviewID,
			decision: .adjusted,
			correctedCount: max(0, min(100, correctedCount)),
			at: date
		)
	}

    /// Legacy changed/not-changed API. Runtime delivery uses receive, which
    /// distinguishes a durable duplicate from a failed save.
    @discardableResult
    public func upsert(_ incoming: DetectionReview) -> Bool {
        let before = reviews
        guard receive(incoming) else { return false }
        return before != reviews
    }

    /// True means the canonical journal and derived repository are durable.
    /// Failed derivation keeps the transport inbox entry retryable.
    @discardableResult
    public func receive(_ incoming: DetectionReview) -> Bool {
        guard incoming.hasValidDates else {
            lastPersistenceError = "The received review contains an invalid date."
            return false
        }
        var next = reviews
        Self.merge(incoming, into: &next)
        let changedIDs = Set(next.filter { item in reviews.first(where: { $0.id == item.id }) != item }.map(\.id))
        var pending = pendingTransmissionIDs.union(changedIDs)
        if let canonical = next.first(where: { $0.id == incoming.id }), canonical != incoming {
            pending.insert(canonical.id)
        }
        if next != reviews || pending != pendingTransmissionIDs {
            guard persist(next, pending: pending) else { return false }
        }
        guard correctionRepository != nil else { return loadFailed == false }
        return retryPendingCorrections()
    }

    private static func mergeSnapshots(_ first: [SmokingEvent], _ second: [SmokingEvent], scope: [UUID]) -> [SmokingEvent] {
        let ids = Set(scope)
        var byID = Dictionary(first.filter { ids.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for event in second where ids.contains(event.id) {
            if let current = byID[event.id] {
                // Original records are immutable. Resolve malformed conflicting
                // copies consistently without making message arrival significant.
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let a = (try? encoder.encode(current)) ?? Data()
                let b = (try? encoder.encode(event)) ?? Data()
                if a.lexicographicallyPrecedes(b) { byID[event.id] = event }
            } else { byID[event.id] = event }
        }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func merge(_ incoming: DetectionReview, into result: inout [DetectionReview]) {
        guard let index = result.firstIndex(where: { $0.id == incoming.id }) else {
            var normalized = incoming
            normalized.eventSnapshots = mergeSnapshots(incoming.eventSnapshots, [], scope: incoming.eventIDs)
            result.append(normalized)
            return
        }
        let current = result[index]
        if current.decision == .pending && incoming.decision == .pending {
            let currentIDs = Set(current.eventIDs)
            let incomingIDs = Set(incoming.eventIDs)
            var merged = incoming.isPreferred(to: current) ? incoming : current
            if currentIDs == incomingIDs, current.eventIDs != incoming.eventIDs {
                merged.eventIDs = currentIDs.sorted { $0.uuidString < $1.uuidString }
            } else if incomingIDs.isSubset(of: currentIDs) { merged.eventIDs = current.eventIDs }
            else if currentIDs.isSubset(of: incomingIDs) { merged.eventIDs = incoming.eventIDs }
            else { merged.eventIDs = currentIDs.union(incomingIDs).sorted { $0.uuidString < $1.uuidString } }
            merged.windowStart = min(current.windowStart, incoming.windowStart)
            merged.windowEnd = max(current.windowEnd, incoming.windowEnd)
            merged.updatedAt = max(current.updatedAt, incoming.updatedAt)
            merged.eventSnapshots = mergeSnapshots(current.eventSnapshots, incoming.eventSnapshots, scope: merged.eventIDs)
            result[index] = merged
            return
        }
        let winner: DetectionReview
        let other: DetectionReview
        if current.decision == .pending || (incoming.decision != .pending && incoming.isPreferred(to: current)) {
            winner = incoming; other = current
        } else { winner = current; other = incoming }
        var canonical = winner
        canonical.eventSnapshots = mergeSnapshots(current.eventSnapshots, incoming.eventSnapshots, scope: winner.eventIDs)
        result[index] = canonical
        let scope = Set(winner.eventIDs)
        let extraIDs = other.eventIDs.filter { scope.contains($0) == false }
        if extraIDs.isEmpty == false {
            let continuation = DetectionReview(
                id: stableID(for: "ciggy-review-continuation-v1:\(winner.id.uuidString)"),
                eventIDs: extraIDs, origin: other.origin,
                windowStart: other.windowStart, windowEnd: other.windowEnd,
                updatedAt: other.updatedAt, revision: other.revision, dayStart: other.dayStart,
                eventSnapshots: mergeSnapshots(other.eventSnapshots, [], scope: extraIDs),
                continuationOf: winner.id
            )
            merge(continuation, into: &result)
        }
    }

    private func updatePending(
        reviewID: UUID, decision: DetectionReviewDecision, correctedCount: Int?, at date: Date
    ) -> DetectionReview? {
        guard date.timeIntervalSince1970.isFinite, date >= .distantPast, date <= .distantFuture else { return nil }
        guard let effective = activeReviews.first(where: { $0.id == reviewID }),
              let index = reviews.firstIndex(where: { $0.id == reviewID }) else {
            lastPersistenceError = "This review has been replaced by a newer summary."
            return nil
        }
        if effective.decision != .pending {
            if effective.correction != nil, effective.decision == decision, effective.correctedCount == correctedCount {
                return reviews[index] // Retry an already journaled decision; never invent a second operation.
            }
            lastPersistenceError = "This summary was already reviewed on another device. Close it and check the saved count."
            return nil
        }
        var review = effective
        review.decision = decision
        review.correctedCount = correctedCount
        review.reviewedAt = date
        review.updatedAt = date
        review.correction = DetectionCorrection(decidedAt: date)
        if review.revision < Int.max { review.revision += 1 }
        review.eventSnapshots = Self.mergeSnapshots(review.eventSnapshots,
            correctionRepository?.originalEvents(for: review.eventIDs) ?? [], scope: review.eventIDs)
        var next = reviews
        next[index] = review
        guard persist(next, pending: pendingTransmissionIDs.union([review.id])) else { return nil }
        return review
    }

    private func load() {
        do {
            let fileData = try snapshotFile?.load()
            guard let data = fileData ?? userDefaults.data(forKey: storageKey) else { return }
            if let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
                guard saved.reviews.allSatisfy(\.hasValidDates) else { throw CocoaError(.fileReadCorruptFile) }
                reviews = Self.sorted(saved.reviews)
                pendingTransmissionIDs = saved.pendingTransmissionIDs
            } else if fileData == nil, let legacy = try? JSONDecoder().decode([DetectionReview].self, from: data) {
                reviews = Self.sorted(legacy.filter(\.hasValidDates))
                // Legacy terminal decisions already changed individual events.
                // Do not replay or reverse them as new correction transactions.
            } else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            loadFailed = true
            lastPersistenceError = "Could not read saved reviews: \(error.localizedDescription)"
        }
    }

    private static func sorted(_ items: [DetectionReview]) -> [DetectionReview] {
        items.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    private func persist(_ items: [DetectionReview], pending: Set<UUID>) -> Bool {
        guard loadFailed == false else { return false }
        do {
            let sorted = Self.sorted(items)
            let data = try JSONEncoder().encode(Snapshot(reviews: sorted, pendingTransmissionIDs: pending))
            if let snapshotWriter { try snapshotWriter(data) }
            else if let snapshotFile { try snapshotFile.write(data) }
            else { userDefaults.set(data, forKey: storageKey) }
            pendingTransmissionIDs = pending
            if reviews != sorted { reviews = sorted }
            lastPersistenceError = nil
            return true
        } catch {
            lastPersistenceError = "Could not save the review: \(error.localizedDescription)"
            return false
        }
    }

    fileprivate func prepareWorkflow(repository: EventRepository? = nil) {
        if let repository { correctionRepository = repository }
        if enqueueReview == nil { enqueueReview = { ConnectivityManager.shared.send(review: $0) } }
    }

}

/// Journals review feedback, derives its event effects, and queues the complete decision.
public enum DetectionReviewWorkflow {
    @MainActor
    @discardableResult
    public static func markAccurate(_ review: DetectionReview, store: DetectionReviewStore) -> Bool {
        store.prepareWorkflow()
        guard store.markAccurate(reviewID: review.id) != nil else { return false }
        return store.retryPendingCorrections()
    }

    @MainActor
    @discardableResult
    public static func adjust(_ review: DetectionReview, to correctedCount: Int,
                              repository: EventRepository, store: DetectionReviewStore) -> Bool {
        store.prepareWorkflow(repository: repository)
        guard store.markAdjusted(reviewID: review.id, correctedCount: correctedCount) != nil else { return false }
        return store.retryPendingCorrections()
    }

	/// Creates an intentional debug-only experience without waiting eight hours for sensors.
	@MainActor
	@discardableResult
	public static func createHistoricalPreview(
		repository: EventRepository,
		store: DetectionReviewStore,
		now: Date = Date()
	) -> DetectionReview? {
		let offsets: [TimeInterval] = [
			-7.5 * 3_600,
			-6.1 * 3_600,
			-4.8 * 3_600,
			-3.2 * 3_600,
			-1.6 * 3_600,
			-0.3 * 3_600
		]
		let events = offsets.map {
			SmokingEvent(
				timestamp: now.addingTimeInterval($0),
				source: .automatic,
				notes: "Historical detection preview",
                motionSessionStartedAt: now.addingTimeInterval($0 - 300)
			)
		}
        let accepted = events.filter { repository.addEvent($0) }
		let reviews = store.recordDaily(
			events: accepted,
			origin: .watchHistory,
			windowStart: now.addingTimeInterval(-8 * 3_600),
			windowEnd: now,
			mergeWithPending: false
		)
		for review in reviews { ConnectivityManager.shared.send(review: review) }
		return reviews.last
	}
}
