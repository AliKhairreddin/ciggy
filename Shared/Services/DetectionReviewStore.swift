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
		return reviews.filter { replaced.contains($0.id) == false }
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

	private let userDefaults: UserDefaults
	private let storageKey: String

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionReviewStore.reviews.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		load()
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
		let validEvents = events.filter { $0.timestamp.timeIntervalSince1970.isFinite &&
			$0.timestamp >= .distantPast && $0.timestamp <= .distantFuture }
		let grouped = Dictionary(grouping: validEvents) { calendar.startOfDay(for: $0.timestamp) }
		let replacedIDs = Set(reviews.compactMap(\.parentReviewID))
		var result: [DetectionReview] = []
		for day in grouped.keys.sorted() {
			guard let dailyEvents = grouped[day]?.sorted(by: { $0.timestamp < $1.timestamp }),
			      let first = dailyEvents.first, let last = dailyEvents.last,
			      let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
			let start = min(first.timestamp, max(day, min(windowStart, windowEnd)))
			let end = max(last.timestamp, min(nextDay.addingTimeInterval(-0.001), max(windowStart, windowEnd)))
			let ids = dailyEvents.map(\.id)
			if mergeWithPending, let index = reviews.lastIndex(where: {
				$0.decision == .pending && $0.origin == origin && $0.dayStart == day &&
				replacedIDs.contains($0.id) == false
			}) {
				var review = reviews[index]
				var seen = Set(review.eventIDs)
				review.eventIDs.append(contentsOf: ids.filter { seen.insert($0).inserted })
				review.windowStart = min(review.windowStart, start)
				review.windowEnd = max(review.windowEnd, end)
				review.updatedAt = updatedAt
				if review.revision < Int.max { review.revision += 1 }
				reviews[index] = review
				result.append(review)
			} else {
				let review = DetectionReview(eventIDs: ids, origin: origin, windowStart: start,
				                             windowEnd: end, updatedAt: updatedAt, dayStart: day)
				reviews.append(review)
				result.append(review)
			}
		}
		if result.isEmpty == false { sortAndSave() }
		return result
	}

	/// Wait for every event before migrating an older summary: review messages can
	/// arrive before their event messages. Both devices derive the same child IDs.
	@discardableResult
	public func normalizePendingReviews(events: [SmokingEvent], calendar: Calendar = .current) -> [DetectionReview] {
		let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		var created: [DetectionReview] = []
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
				                            updatedAt: legacy.updatedAt, dayStart: day, parentReviewID: legacy.id)
				guard reviews.contains(where: { $0.id == child.id }) == false else { continue }
				reviews.append(child)
				created.append(child)
			}
		}
		if created.isEmpty == false { sortAndSave() }
		return created
	}

	private static func dailyID(parent: UUID, eventIDs: [UUID]) -> UUID {
		let key = "ciggy-daily-review-v1:\(parent.uuidString):" + eventIDs.map(\.uuidString).sorted().joined(separator: ":")
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

	/// Merges a remote revision without duplicating an at-least-once delivery.
	@discardableResult
	public func upsert(_ incoming: DetectionReview) -> Bool {
		guard incoming.hasValidDates else { return false }
		guard let index = reviews.firstIndex(where: { $0.id == incoming.id }) else {
			reviews.append(incoming)
			sortAndSave()
			return true
		}
		let current = reviews[index]
		guard incoming.revision > current.revision ||
			(incoming.revision == current.revision && incoming.updatedAt > current.updatedAt) else {
			return false
		}
		reviews[index] = incoming
		sortAndSave()
		return true
	}

	public func removeAll() {
		reviews.removeAll()
		save()
	}

	private func updatePending(
		reviewID: UUID,
		decision: DetectionReviewDecision,
		correctedCount: Int?,
		at date: Date
	) -> DetectionReview? {
		guard date.timeIntervalSince1970.isFinite, date >= .distantPast, date <= .distantFuture else { return nil }
		guard activeReviews.contains(where: { $0.id == reviewID }),
		      let index = reviews.firstIndex(where: { $0.id == reviewID }),
		      reviews[index].decision == .pending else { return nil }
		var review = reviews[index]
		review.decision = decision
		review.correctedCount = correctedCount
		review.reviewedAt = date
		review.updatedAt = date
		if review.revision < Int.max { review.revision += 1 }
		reviews[index] = review
		sortAndSave()
		return review
	}

	private func load() {
		guard let data = userDefaults.data(forKey: storageKey),
		      let decoded = try? JSONDecoder().decode([DetectionReview].self, from: data) else {
			reviews = []
			return
		}
		reviews = decoded.filter(\.hasValidDates).sorted { $0.updatedAt < $1.updatedAt }
	}

	private func sortAndSave() {
		reviews.sort { $0.updatedAt < $1.updatedAt }
		save()
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(reviews) else { return }
		userDefaults.set(data, forKey: storageKey)
	}
}

/// Applies review feedback to the event log and synchronizes every resulting mutation.
public enum DetectionReviewWorkflow {
	@MainActor
	public static func markAccurate(
		_ review: DetectionReview,
		store: DetectionReviewStore
	) {
		guard let updated = store.markAccurate(reviewID: review.id) else { return }
		ConnectivityManager.shared.send(review: updated)
	}

	@MainActor
	public static func adjust(
		_ review: DetectionReview,
		to correctedCount: Int,
		repository: EventRepository,
		store: DetectionReviewStore
	) {
		let correctedCount = max(0, min(100, correctedCount))
		guard let updated = store.markAdjusted(
			reviewID: review.id,
			correctedCount: correctedCount
		) else { return }

		// The summary may have merged new detections while its adjustment sheet was open.
		// Apply the decision to the latest persisted revision returned by the store.
		if correctedCount < updated.originalCount {
			for eventID in updated.eventIDs.suffix(updated.originalCount - correctedCount) {
				repository.removeEvent(id: eventID)
				ConnectivityManager.shared.sendDeletedEvent(id: eventID)
			}
		} else if correctedCount > updated.originalCount {
			let additionalCount = correctedCount - updated.originalCount
			let duration = max(0, updated.windowEnd.timeIntervalSince(updated.windowStart))
			for index in 0..<additionalCount {
				let fraction = Double(index + 1) / Double(additionalCount + 1)
				let event = SmokingEvent(
					timestamp: updated.windowStart.addingTimeInterval(duration * fraction),
					source: .manual,
					notes: "Added while adjusting a Watch detection summary."
				)
				repository.addEvent(event)
				ConnectivityManager.shared.send(event: event)
			}
		}

		ConnectivityManager.shared.send(review: updated)
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
				notes: "Historical detection preview"
			)
		}
		for event in events {
			repository.addEvent(event)
			ConnectivityManager.shared.send(event: event)
		}
		let reviews = store.recordDaily(
			events: events,
			origin: .watchHistory,
			windowStart: now.addingTimeInterval(-8 * 3_600),
			windowEnd: now,
			mergeWithPending: false
		)
		for review in reviews { ConnectivityManager.shared.send(review: review) }
		return reviews.last
	}
}
