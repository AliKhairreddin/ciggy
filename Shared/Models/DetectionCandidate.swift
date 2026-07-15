import Foundation

/// A sensor signal that may represent smoking and still needs a person's review.
public struct DetectionCandidate: Identifiable, Codable, Equatable, Sendable {
	public let id: UUID
	public let gestureAt: Date
	public let detectedAt: Date
	public let baselineHeartRate: Double
	public let peakHeartRate: Double

	public init(
		id: UUID = UUID(),
		gestureAt: Date,
		detectedAt: Date,
		baselineHeartRate: Double,
		peakHeartRate: Double
	) {
		self.id = id
		self.gestureAt = gestureAt
		self.detectedAt = detectedAt
		self.baselineHeartRate = baselineHeartRate
		self.peakHeartRate = peakHeartRate
	}

	public var heartRateIncrease: Double {
		peakHeartRate - baselineHeartRate
	}

	/// Converts a reviewed candidate into a stored event. Call only after confirmation.
	public func confirmedEvent(notes: String? = nil) -> SmokingEvent {
		SmokingEvent(
			id: id,
			timestamp: gestureAt,
			source: .automatic,
			heartRate: peakHeartRate,
			notes: notes
		)
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
