import Foundation

/// A bounded snapshot of today's logs, shared by the app and its Live Activity.
public struct LiveActivitySnapshot: Codable, Hashable, Sendable {
	public let dayStart: Date
	public let dailyCount: Int
	public let dailyLimit: Int
	public let lastLoggedAt: Date?

	public init(events: [SmokingEvent], dailyLimit: Int, now: Date = Date(), calendar: Calendar = .current) {
		var seen = Set<UUID>()
		let dates = events.filter { seen.insert($0.id).inserted }.map(\.timestamp)
		self.init(loggedAt: dates, dailyLimit: dailyLimit, now: now, calendar: calendar)
	}

	public init(loggedAt: [Date], dailyLimit: Int, now: Date = Date(), calendar: Calendar = .current) {
		let start = calendar.startOfDay(for: now)
		dayStart = start
		self.dailyLimit = UserSettings.clampedDailyLimit(dailyLimit)
		let validDates = loggedAt.filter { $0 <= now }
		dailyCount = validDates.filter { $0 >= start }.count
		lastLoggedAt = validDates.max()
	}

	public var remaining: Int { max(0, dailyLimit - dailyCount) }
	public var progress: Double { min(1, Double(dailyCount) / Double(dailyLimit)) }

	/// Do not carry yesterday's total into a new day, or exceed ActivityKit's eight-hour limit.
	public static func expiration(startingAt date: Date, calendar: Calendar = .current) -> Date {
		let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
		return min(midnight, date.addingTimeInterval(8 * 60 * 60))
	}
}
