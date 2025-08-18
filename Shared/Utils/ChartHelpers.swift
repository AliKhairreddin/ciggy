import Foundation

public struct DayCount: Identifiable, Hashable, Sendable {
	public let id: String
	public let date: Date
	public let count: Int

	public init(date: Date, count: Int) {
		self.date = date
		self.count = count
		let df = DateFormatter()
		df.dateFormat = "yyyy-MM-dd"
		self.id = df.string(from: date)
	}
}

public enum ChartHelpers {
	/// Groups events per day over the last N days ending today
	public static func dayCounts(for events: [SmokingEvent], lastNDays: Int = 7) -> [DayCount] {
		let calendar = Calendar.current
		let today = Date().startOfDayInCurrentCalendar
		var buckets: [Date: Int] = [:]
		for i in 0..<lastNDays {
			if let date = calendar.date(byAdding: .day, value: -i, to: today) {
				buckets[date] = 0
			}
		}
		for e in events {
			let d = e.timestamp.startOfDayInCurrentCalendar
			if buckets[d] != nil { buckets[d, default: 0] += 1 }
		}
		return buckets
			.sorted { $0.key < $1.key }
			.map { DayCount(date: $0.key, count: $0.value) }
	}
}


