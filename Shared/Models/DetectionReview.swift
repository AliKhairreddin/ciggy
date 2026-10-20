import Foundation

/// Where an automatic smoking detection was observed.
public enum DetectionReviewOrigin: String, Codable, Equatable, Sendable {
	case liveWatch
	case watchHistory
}

/// A summary remains passive until the user chooses to teach the detector.
public enum DetectionReviewDecision: String, Codable, Equatable, Sendable {
	case pending
	case accurate
	case adjusted
}

/// A synchronized, non-blocking review of one or more automatically logged events.
public struct DetectionReview: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public var eventIDs: [UUID]
	public var origin: DetectionReviewOrigin
	public var windowStart: Date
	public var windowEnd: Date
	public var decision: DetectionReviewDecision
	public var correctedCount: Int?
	public var reviewedAt: Date?
	public var updatedAt: Date
	/// Monotonic merge key used when WatchConnectivity delivers updates at least once.
	public var revision: Int

	public init(
		id: UUID = UUID(),
		eventIDs: [UUID],
		origin: DetectionReviewOrigin,
		windowStart: Date,
		windowEnd: Date,
		decision: DetectionReviewDecision = .pending,
		correctedCount: Int? = nil,
		reviewedAt: Date? = nil,
		updatedAt: Date = Date(),
		revision: Int = 1
	) {
		self.id = id
		self.eventIDs = Self.unique(eventIDs)
		self.origin = origin
		self.windowStart = min(windowStart, windowEnd)
		self.windowEnd = max(windowStart, windowEnd)
		self.decision = decision
		self.correctedCount = correctedCount.map { max(0, min(100, $0)) }
		self.reviewedAt = reviewedAt
		self.updatedAt = updatedAt
		self.revision = max(1, revision)
	}

	public var originalCount: Int { eventIDs.count }
	public var displayCount: Int { correctedCount ?? originalCount }

	public var historyHours: Int {
		let hours = ceil(windowEnd.timeIntervalSince(windowStart) / 3_600)
		guard hours.isFinite, hours > 0 else { return 1 }
		// A malformed persisted date must never trap during a Double-to-Int conversion.
		return Int(min(hours, Double(Int.max / 2)))
	}

	var hasValidDates: Bool {
		[windowStart, windowEnd, updatedAt].allSatisfy {
			$0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture
		} && (reviewedAt.map { $0.timeIntervalSince1970.isFinite && $0 >= .distantPast && $0 <= .distantFuture } ?? true)
	}

	/// Decode through the initializer so received and saved reviews have the same invariants.
	public init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		self.init(
			id: try values.decode(UUID.self, forKey: .id),
			eventIDs: try values.decode([UUID].self, forKey: .eventIDs),
			origin: try values.decode(DetectionReviewOrigin.self, forKey: .origin),
			windowStart: try values.decode(Date.self, forKey: .windowStart),
			windowEnd: try values.decode(Date.self, forKey: .windowEnd),
			decision: try values.decode(DetectionReviewDecision.self, forKey: .decision),
			correctedCount: try values.decodeIfPresent(Int.self, forKey: .correctedCount),
			reviewedAt: try values.decodeIfPresent(Date.self, forKey: .reviewedAt),
			updatedAt: try values.decode(Date.self, forKey: .updatedAt),
			revision: try values.decode(Int.self, forKey: .revision)
		)
	}

	private static func unique(_ ids: [UUID]) -> [UUID] {
		var seen = Set<UUID>()
		return ids.filter { seen.insert($0).inserted }
	}
}
