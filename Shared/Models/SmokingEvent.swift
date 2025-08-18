import Foundation

/// Source of a smoking event: automatically detected vs manually logged
public enum SmokingEventSource: String, Codable, CaseIterable, Sendable {
	case automatic
	case manual
}

/// Represents one smoking event instance
public struct SmokingEvent: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public let timestamp: Date
	public let source: SmokingEventSource
	public let heartRate: Double?
	public var notes: String?

	public init(
		id: UUID = UUID(),
		timestamp: Date = Date(),
		source: SmokingEventSource,
		heartRate: Double? = nil,
		notes: String? = nil
	) {
		self.id = id
		self.timestamp = timestamp
		self.source = source
		self.heartRate = heartRate
		self.notes = notes
	}
}

public extension SmokingEvent {
	/// Day key used for grouping (yyyy-MM-dd in the user's current calendar/timezone)
	var dayKey: String {
		let df = DateFormatter()
		df.calendar = Calendar.current
		df.locale = Locale.autoupdatingCurrent
		df.timeZone = TimeZone.autoupdatingCurrent
		df.dateFormat = "yyyy-MM-dd"
		return df.string(from: timestamp)
	}

	/// Mock events for previews/testing
	static func mock(count: Int = 12, startDaysAgo: Int = 7) -> [SmokingEvent] {
		let calendar = Calendar.current
		let now = Date()
		return (0..<count).map { idx in
			let days = Int.random(in: 0...max(startDaysAgo, 1))
			let minutes = Int.random(in: 0...23*60)
			let date = calendar.date(byAdding: .day, value: -days, to: now) ?? now
			let ts = calendar.date(byAdding: .minute, value: -minutes, to: date) ?? date
			return SmokingEvent(
				timestamp: ts,
				source: Bool.random() ? .automatic : .manual,
				heartRate: Double.random(in: 60...120),
				notes: Bool.random() ? "Quick note" : nil
			)
		}.sorted { $0.timestamp < $1.timestamp }
	}
}


