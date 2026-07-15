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
		self.correctedCount = correctedCount
		self.reviewedAt = reviewedAt
		self.updatedAt = updatedAt
		self.revision = max(1, revision)
	}

	public var originalCount: Int { eventIDs.count }
	public var displayCount: Int { correctedCount ?? originalCount }

	public var historyHours: Int {
		max(1, Int(ceil(windowEnd.timeIntervalSince(windowStart) / 3_600)))
	}

	private static func unique(_ ids: [UUID]) -> [UUID] {
		var seen = Set<UUID>()
		return ids.filter { seen.insert($0).inserted }
	}
}
