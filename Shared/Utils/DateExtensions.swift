import Foundation

public extension Date {
	/// Returns the start of day in the current calendar/timezone
	var startOfDayInCurrentCalendar: Date {
		Calendar.current.startOfDay(for: self)
	}

	/// Human-friendly relative time (e.g., "2h 15m ago")
	func shortRelativeDescription(to reference: Date = Date()) -> String {
		let seconds = max(0, Int(reference.timeIntervalSince(self)))
		if seconds < 60 { return "just now" }
		let minutes = seconds / 60
		if minutes < 60 { return "\(minutes)m ago" }
		let hours = minutes / 60
		if hours < 24 {
			let rem = minutes % 60
			return rem > 0 ? "\(hours)h \(rem)m ago" : "\(hours)h ago"
		}
		let days = hours / 24
		return days == 1 ? "1 day ago" : "\(days) days ago"
	}

	/// Inclusive day difference
	func daysSince(_ other: Date) -> Int {
		let startSelf = self.startOfDayInCurrentCalendar
		let startOther = other.startOfDayInCurrentCalendar
		let comps = Calendar.current.dateComponents([.day], from: startOther, to: startSelf)
		return comps.day ?? 0
	}
}


