import Foundation

/// A sensor signal that may represent smoking and can be reviewed after it is logged.
public struct DetectionCandidate: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public let gestureAt: Date
	public let detectedAt: Date
	/// Start of the repeated hand-to-mouth pattern that formed this candidate.
	public let motionSessionStartedAt: Date?
	/// Number of distinct raise/lower cycles observed in the motion session.
	public let motionGestureCount: Int?
	/// Optional context only. Motion can create a candidate without HealthKit data.
	public let baselineHeartRate: Double?
	public let peakHeartRate: Double?

	public init(
		id: UUID = UUID(),
		gestureAt: Date,
		detectedAt: Date,
		motionSessionStartedAt: Date? = nil,
		motionGestureCount: Int? = nil,
		baselineHeartRate: Double? = nil,
		peakHeartRate: Double? = nil
	) {
		self.id = id
		self.gestureAt = gestureAt
		self.detectedAt = detectedAt
		self.motionSessionStartedAt = motionSessionStartedAt
		self.motionGestureCount = motionGestureCount
		self.baselineHeartRate = baselineHeartRate
		self.peakHeartRate = peakHeartRate
	}

	public var heartRateIncrease: Double? {
		guard let baselineHeartRate, let peakHeartRate else { return nil }
		return peakHeartRate - baselineHeartRate
	}

	/// Converts a motion candidate into the automatic event shown in a passive summary.
	public func detectedEvent(notes: String? = nil) -> SmokingEvent {
		SmokingEvent(
			id: id,
			timestamp: gestureAt,
			source: .automatic,
			heartRate: peakHeartRate,
			notes: notes
		)
	}

	/// Backward-compatible alias for older callers and stored confirmation flows.
	public func confirmedEvent(notes: String? = nil) -> SmokingEvent {
		detectedEvent(notes: notes)
	}
}

public enum DetectionFeedbackDecision: String, Codable, Equatable, Sendable {
	case confirmed
	case dismissed
}

/// The user's response to an assisted-detection prompt.
public struct DetectionFeedback: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public let candidate: DetectionCandidate
	public let decision: DetectionFeedbackDecision
	public let decidedAt: Date

	public init(
		id: UUID = UUID(),
		candidate: DetectionCandidate,
		decision: DetectionFeedbackDecision,
		decidedAt: Date = Date()
	) {
		self.id = id
		self.candidate = candidate
		self.decision = decision
		self.decidedAt = decidedAt
	}
}
