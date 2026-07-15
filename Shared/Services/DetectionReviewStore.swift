import Combine
import Foundation

/// Persists and merges the passive detection summaries shown on iPhone and Apple Watch.
@MainActor
public final class DetectionReviewStore: ObservableObject {
	@Published public private(set) var reviews: [DetectionReview] = []

	public var latestReview: DetectionReview? {
		reviews.max { $0.updatedAt < $1.updatedAt }
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

	/// Records new automatic events and rolls nearby, unreviewed detections into one summary.
	@discardableResult
	public func record(
		events: [SmokingEvent],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		at updatedAt: Date = Date(),
		mergeWithPending: Bool = true
	) -> DetectionReview? {
		let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
		guard sortedEvents.isEmpty == false else { return nil }
		let eventIDs = sortedEvents.map(\.id)

		if mergeWithPending,
		   let index = reviews.lastIndex(where: {
			$0.decision == .pending &&
			$0.origin == origin &&
			windowStart <= $0.windowEnd.addingTimeInterval(8 * 60 * 60) &&
			windowEnd >= $0.windowStart.addingTimeInterval(-8 * 60 * 60)
		   }) {
			var review = reviews[index]
			var seen = Set(review.eventIDs)
			review.eventIDs.append(contentsOf: eventIDs.filter { seen.insert($0).inserted })
			review.windowStart = min(review.windowStart, windowStart)
			review.windowEnd = max(review.windowEnd, windowEnd)
			review.updatedAt = updatedAt
			review.revision += 1
			reviews[index] = review
			sortAndSave()
			return review
		}

		let review = DetectionReview(
			eventIDs: eventIDs,
			origin: origin,
			windowStart: windowStart,
			windowEnd: windowEnd,
			updatedAt: updatedAt
		)
		reviews.append(review)
		sortAndSave()
		return review
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
		guard let index = reviews.firstIndex(where: { $0.id == reviewID }),
		      reviews[index].decision == .pending else { return nil }
		var review = reviews[index]
		review.decision = decision
		review.correctedCount = correctedCount
		review.reviewedAt = date
		review.updatedAt = date
		review.revision += 1
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
		reviews = decoded.sorted { $0.updatedAt < $1.updatedAt }
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

		if correctedCount < review.originalCount {
			for eventID in review.eventIDs.suffix(review.originalCount - correctedCount) {
				repository.removeEvent(id: eventID)
				ConnectivityManager.shared.sendDeletedEvent(id: eventID)
			}
		} else if correctedCount > review.originalCount {
			let additionalCount = correctedCount - review.originalCount
			let duration = max(60, review.windowEnd.timeIntervalSince(review.windowStart))
			for index in 0..<additionalCount {
				let fraction = Double(index + 1) / Double(additionalCount + 1)
				let event = SmokingEvent(
					timestamp: review.windowStart.addingTimeInterval(duration * fraction),
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
		guard let review = store.record(
			events: events,
			origin: .watchHistory,
			windowStart: now.addingTimeInterval(-8 * 3_600),
			windowEnd: now,
			mergeWithPending: false
		) else { return nil }
		ConnectivityManager.shared.send(review: review)
		return review
	}
}
