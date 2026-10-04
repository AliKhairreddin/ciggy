import Foundation

/// Only timestamps and the goal leave the app's store; notes and health data stay private.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
	public let loggedAt: [Date]
	public let dailyLimit: Int

	public init(events: [SmokingEvent], dailyLimit: Int, now: Date = Date()) {
		var seen = Set<UUID>()
		let dates = events.filter { seen.insert($0.id).inserted && $0.timestamp <= now }.map(\.timestamp).sorted()
		let cutoff = now.addingTimeInterval(-8 * 24 * 60 * 60)
		// Keep enough for seven calendar days, plus the last log even if it was longer ago.
		loggedAt = dates.filter { $0 >= cutoff || $0 == dates.last }
		self.dailyLimit = UserSettings.clampedDailyLimit(dailyLimit)
	}

	public func today(at date: Date, calendar: Calendar = .current) -> LiveActivitySnapshot {
		LiveActivitySnapshot(loggedAt: loggedAt, dailyLimit: dailyLimit, now: date, calendar: calendar)
	}

	public func week(at date: Date, calendar: Calendar = .current) -> [Day] {
		let start = calendar.startOfDay(for: date)
		return (-6...0).compactMap { offset in
			guard let day = calendar.date(byAdding: .day, value: offset, to: start),
			      let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
			return Day(date: day, count: loggedAt.filter { $0 >= day && $0 < end && $0 <= date }.count)
		}
	}

	public struct Day: Identifiable, Sendable {
		public let date: Date
		public let count: Int
		public var id: Date { date }
	}
}
