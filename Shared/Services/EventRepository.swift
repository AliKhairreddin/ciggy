import Foundation
import Combine

/// In-memory + UserDefaults persisted repository for smoking events.
/// In later phases, this can sync with Firebase and CloudKit.
@MainActor
public final class EventRepository: ObservableObject {
	@Published public private(set) var events: [SmokingEvent] = []

	private let storageKey = "EventRepository.events.v1"

	public init() {
		load()
	}

	public func addEvent(_ event: SmokingEvent) {
		guard events.contains(where: { $0.id == event.id }) == false else { return }
		events.append(event)
		events.sort { $0.timestamp < $1.timestamp }
		save()
	}

	public func removeAll() {
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
	/// The search is bounded by the oldest stored event so an empty repository does not
	/// produce an unbounded loop. With no history, the user has a one-day current streak.
	public func streakSmokeFreeDays(considering day: Date = Date()) -> Int {
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
		guard let data = UserDefaults.standard.data(forKey: storageKey),
			let decoded = try? JSONDecoder().decode([SmokingEvent].self, from: data) else {
			events = []
			return
		}
		events = decoded.sorted { $0.timestamp < $1.timestamp }
	}

	private func save() {
		if let data = try? JSONEncoder().encode(events) {
			UserDefaults.standard.set(data, forKey: storageKey)
		}
	}
}


