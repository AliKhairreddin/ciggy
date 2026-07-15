import Foundation

/// Groups repeated hand-to-mouth gestures into one probable smoking session.
///
/// Motion is the primary signal. Heart-rate samples are retained only to attach
/// optional context to the candidate and are never required for detection.
public struct DetectionFusionEngine: Sendable {
	public struct Configuration: Sendable, Equatable {
		public var minimumGestureCount: Int
		public var sessionWindowSeconds: TimeInterval
		public var minimumGestureSeparationSeconds: TimeInterval
		public var maximumGestureSeparationSeconds: TimeInterval
		public var detectionCooldownSeconds: TimeInterval
		public var heartRateContextSeconds: TimeInterval

		public init(
			minimumGestureCount: Int = 5,
			sessionWindowSeconds: TimeInterval = 8 * 60,
			minimumGestureSeparationSeconds: TimeInterval = 6,
			maximumGestureSeparationSeconds: TimeInterval = 2.5 * 60,
			detectionCooldownSeconds: TimeInterval = 8 * 60,
			heartRateContextSeconds: TimeInterval = 60
		) {
			self.minimumGestureCount = max(2, minimumGestureCount)
			self.sessionWindowSeconds = max(30, sessionWindowSeconds)
			self.minimumGestureSeparationSeconds = max(0, minimumGestureSeparationSeconds)
			self.maximumGestureSeparationSeconds = max(
				self.minimumGestureSeparationSeconds,
				maximumGestureSeparationSeconds
			)
			self.detectionCooldownSeconds = max(0, detectionCooldownSeconds)
			self.heartRateContextSeconds = max(10, heartRateContextSeconds)
		}
	}

	public private(set) var configuration: Configuration
	public var hasActiveMotionSession: Bool { gestureTimestamps.isEmpty == false }
	public var observedGestureCount: Int { gestureTimestamps.count }

	private var recentHeartRates: [(timestamp: Date, bpm: Double)] = []
	private var gestureTimestamps: [Date] = []
	private var lastCandidateAt: Date?

	public init(configuration: Configuration = .init()) {
		self.configuration = configuration
	}

	/// Higher sensitivity asks for fewer repeated movements; it never changes
	/// the core requirement that multiple separated raise/lower cycles occur.
	public mutating func updateSensitivity(_ sensitivity: Double) {
		let clamped = max(0, min(1, sensitivity))
		switch clamped {
		case ..<0.34:
			configuration.minimumGestureCount = 7
		case 0.67...:
			configuration.minimumGestureCount = 4
		default:
			configuration.minimumGestureCount = 5
		}
	}

	/// Stores optional physiological context. This method never emits a candidate.
	public mutating func recordHeartRate(_ bpm: Double, at timestamp: Date) {
		guard bpm.isFinite, bpm > 0 else { return }
		recentHeartRates.append((timestamp, bpm))
		recentHeartRates.sort { $0.timestamp < $1.timestamp }
		trimHeartRates(relativeTo: timestamp)
	}

	/// Records a distinct hand-to-mouth gesture and emits once the motion pattern
	/// reaches the configured count inside a cigarette-sized time window.
	public mutating func recordGesture(at timestamp: Date) -> DetectionCandidate? {
		if let lastCandidateAt,
		   timestamp.timeIntervalSince(lastCandidateAt) < configuration.detectionCooldownSeconds {
			return nil
		}

		if let lastGesture = gestureTimestamps.last {
			let separation = timestamp.timeIntervalSince(lastGesture)
			guard separation >= configuration.minimumGestureSeparationSeconds else { return nil }
			if separation > configuration.maximumGestureSeparationSeconds {
				gestureTimestamps.removeAll()
			}
		}

		gestureTimestamps.append(timestamp)
		gestureTimestamps.removeAll {
			timestamp.timeIntervalSince($0) > configuration.sessionWindowSeconds
		}

		guard gestureTimestamps.count >= configuration.minimumGestureCount,
		      let sessionStartedAt = gestureTimestamps.first else { return nil }

		let baseline = baselineHeartRate(before: sessionStartedAt)
		let peak = recentHeartRates
			.filter { $0.timestamp >= sessionStartedAt && $0.timestamp <= timestamp }
			.map(\.bpm)
			.max()

		let candidate = DetectionCandidate(
			gestureAt: timestamp,
			detectedAt: timestamp,
			motionSessionStartedAt: sessionStartedAt,
			motionGestureCount: gestureTimestamps.count,
			baselineHeartRate: baseline,
			peakHeartRate: peak
		)
		lastCandidateAt = timestamp
		gestureTimestamps.removeAll()
		return candidate
	}

	private func baselineHeartRate(before timestamp: Date) -> Double? {
		let windowStart = timestamp.addingTimeInterval(-configuration.heartRateContextSeconds)
		let samples = recentHeartRates
			.filter { $0.timestamp >= windowStart && $0.timestamp <= timestamp }
			.suffix(3)
		guard samples.isEmpty == false else { return nil }
		return samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
	}

	private mutating func trimHeartRates(relativeTo timestamp: Date) {
		let retention = configuration.sessionWindowSeconds + configuration.heartRateContextSeconds
		let cutoff = timestamp.addingTimeInterval(-retention)
		recentHeartRates.removeAll { $0.timestamp < cutoff }
	}
}
