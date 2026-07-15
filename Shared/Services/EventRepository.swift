import Foundation
import Combine

/// In-memory + UserDefaults persisted repository for smoking events.
/// In later phases, this can sync with Firebase and CloudKit.
@MainActor
public final class EventRepository: ObservableObject {
	@Published public private(set) var events: [SmokingEvent] = []

	private let userDefaults: UserDefaults
	private let storageKey: String
	private let deletedStorageKey: String
	private var deletedEventIDs: Set<UUID> = []

	public init(
		userDefaults: UserDefaults = .standard,
		storageKey: String = "EventRepository.events.v1"
	) {
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		self.deletedStorageKey = "\(storageKey).deleted.v1"
		load()
	}

	@discardableResult
	public func addEvent(_ event: SmokingEvent) -> Bool {
		guard deletedEventIDs.contains(event.id) == false else { return false }
		guard events.contains(where: { $0.id == event.id }) == false else { return false }
		events.append(event)
		events.sort { $0.timestamp < $1.timestamp }
		save()
		return true
	}

	/// Persists a tombstone so a delayed duplicate transfer cannot restore a correction.
	@discardableResult
	public func removeEvent(id: UUID) -> Bool {
		let hadEvent = events.contains { $0.id == id }
		deletedEventIDs.insert(id)
		events.removeAll { $0.id == id }
		save()
		return hadEvent
	}

	public func removeAll() {
		deletedEventIDs.formUnion(events.map(\.id))
		events.removeAll()
		save()
	}

	public func events(on day: Date) -> [SmokingEvent] {
		let start = day.startOfDayInCurrentCalendar
		let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
		return events.filter { $0.timestamp >= start && $0.timestamp < end }
	}

	public func dailyCount(on day: Date) -> Int {
		events(on: day).count
	}

	/// Returns consecutive smoke-free days ending on the supplied day.
	///
	/// The search is bounded by the oldest stored event. With no history there is not yet
	/// enough evidence to claim a smoke-free streak, so the result is zero.
	public func streakSmokeFreeDays(considering day: Date = Date()) -> Int {
		guard events.isEmpty == false else { return 0 }
		let calendar = Calendar.current
		let targetDay = day.startOfDayInCurrentCalendar
		let earliestDay = events.map { $0.timestamp.startOfDayInCurrentCalendar }.min() ?? targetDay
		var streak = 0
		var cursor = targetDay

		while cursor >= earliestDay {
			if events(on: cursor).isEmpty {
				streak += 1
				guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
				cursor = prev
			} else {
				break
			}
		}

		return streak
	}

	/// Naive money-saved estimate based on cost per cigarette
	public func estimatedMoneySaved(costPerCigarette: Double = 0.6) -> Double {
		// Assumes that each prevented event compared to user's baseline yields savings.
		// For now, we simply multiply streak days by (dailyLimit * cost).
		let baselinePerDay = UserDefaults.standard.integer(forKey: "baselineCigsPerDay")
		let days = streakSmokeFreeDays()
		return Double(baselinePerDay * days) * max(costPerCigarette, 0)
	}

	private func load() {
		if let deletedData = userDefaults.data(forKey: deletedStorageKey),
		   let decodedDeletedIDs = try? JSONDecoder().decode([UUID].self, from: deletedData) {
			deletedEventIDs = Set(decodedDeletedIDs)
		}
		guard let data = userDefaults.data(forKey: storageKey),
			let decoded = try? JSONDecoder().decode([SmokingEvent].self, from: data) else {
			events = []
			return
		}
		events = decoded
			.filter { deletedEventIDs.contains($0.id) == false }
			.sorted { $0.timestamp < $1.timestamp }
	}

	private func save() {
		if let data = try? JSONEncoder().encode(events) {
			userDefaults.set(data, forKey: storageKey)
		}
		if let deletedData = try? JSONEncoder().encode(Array(deletedEventIDs)) {
			userDefaults.set(deletedData, forKey: deletedStorageKey)
		}
	}
}
