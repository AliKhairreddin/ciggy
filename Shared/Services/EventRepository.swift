import Foundation
import Combine

/// In-memory + UserDefaults persisted repository for smoking events.
/// In later phases, this can sync with Firebase and CloudKit.
public final class EventRepository: ObservableObject, Sendable {
	@Published public private(set) var events: [SmokingEvent] = []

	private let storageKey = "EventRepository.events.v1"
	private let queue = DispatchQueue(label: "EventRepository.queue", qos: .userInitiated)

	public init() {
		load()
	}

	public func addEvent(_ event: SmokingEvent) {
		queue.async {
			var copy = self.events
			copy.append(event)
			copy.sort { $0.timestamp < $1.timestamp }
			DispatchQueue.main.async {
				self.events = copy
				self.save()
			}
		}
	}

	public func removeAll() {
		DispatchQueue.main.async {
			self.events.removeAll()
			self.save()
		}
	}

	public func events(on day: Date) -> [SmokingEvent] {
		let start = day.startOfDayInCurrentCalendar
		let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
		return events.filter { $0.timestamp >= start && $0.timestamp < end }
	}

	public func dailyCount(on day: Date) -> Int {
		events(on: day).count
	}

	/// Returns the number of consecutive smoke-free days ending today
	public func streakSmokeFreeDays(considering day: Date = Date()) -> Int {
		var streak = 0
		var cursor = day.startOfDayInCurrentCalendar
		while events(on: cursor).isEmpty {
			streak += 1
			guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
			cursor = prev
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
		if let data = UserDefaults.standard.data(forKey: storageKey),
		   let decoded = try? JSONDecoder().decode([SmokingEvent].self, from: data) {
			self.events = decoded
		} else {
			self.events = SmokingEvent.mock(count: 10)
		}
	}

	private func save() {
		if let data = try? JSONEncoder().encode(events) {
			UserDefaults.standard.set(data, forKey: storageKey)
		}
	}
}


