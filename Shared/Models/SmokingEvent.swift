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
	/// First completed gesture supporting an automatic event; nil for older events.
	public let motionSessionStartedAt: Date?
	public var notes: String?
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, source, heartRate, motionSessionStartedAt, notes
        case timestampReferenceTime, motionSessionReferenceTime
    }

	public init(
		id: UUID = UUID(),
		timestamp: Date = Date(),
		source: SmokingEventSource,
		heartRate: Double? = nil,
		notes: String? = nil,
		motionSessionStartedAt: Date? = nil
	) {
		self.id = id
		self.timestamp = timestamp
		self.source = source
		self.heartRate = heartRate
		self.notes = notes
		self.motionSessionStartedAt = motionSessionStartedAt
	}
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try values.decodeIfPresent(Double.self, forKey: .timestampReferenceTime)
            .map { Date(timeIntervalSinceReferenceDate: $0) } ?? values.decode(Date.self, forKey: .timestamp)
        let sessionStart = try values.decodeIfPresent(Double.self, forKey: .motionSessionReferenceTime)
            .map { Date(timeIntervalSinceReferenceDate: $0) } ?? values.decodeIfPresent(Date.self, forKey: .motionSessionStartedAt)
        self.init(id: try values.decode(UUID.self, forKey: .id), timestamp: timestamp,
                  source: try values.decode(SmokingEventSource.self, forKey: .source),
                  heartRate: try values.decodeIfPresent(Double.self, forKey: .heartRate),
                  notes: try values.decodeIfPresent(String.self, forKey: .notes), motionSessionStartedAt: sessionStart)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(timestamp, forKey: .timestamp)
        try values.encode(timestamp.timeIntervalSinceReferenceDate, forKey: .timestampReferenceTime)
        try values.encode(source, forKey: .source)
        try values.encodeIfPresent(heartRate, forKey: .heartRate)
        try values.encodeIfPresent(notes, forKey: .notes)
        try values.encodeIfPresent(motionSessionStartedAt, forKey: .motionSessionStartedAt)
        try values.encodeIfPresent(motionSessionStartedAt?.timeIntervalSinceReferenceDate, forKey: .motionSessionReferenceTime)
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
		guard count > 0 else { return [] }
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


