import Foundation

/// Deterministic state machine that correlates a motion gesture with later heart-rate samples.
///
/// It intentionally has no framework dependencies so the fusion behavior can be unit tested.
public struct DetectionFusionEngine: Sendable {
	public struct Configuration: Sendable, Equatable {
		public var heartRateSpikeBPM: Double
		public var fusionWindowSeconds: TimeInterval
		public var detectionCooldownSeconds: TimeInterval
		public var minimumPostGestureSamples: Int

		public init(
			heartRateSpikeBPM: Double = 10,
			fusionWindowSeconds: TimeInterval = 20,
			detectionCooldownSeconds: TimeInterval = 8 * 60,
			minimumPostGestureSamples: Int = 2
		) {
			self.heartRateSpikeBPM = max(0, heartRateSpikeBPM)
			self.fusionWindowSeconds = max(1, fusionWindowSeconds)
			self.detectionCooldownSeconds = max(0, detectionCooldownSeconds)
			self.minimumPostGestureSamples = max(1, minimumPostGestureSamples)
		}
	}

	private struct PendingGesture: Sendable {
		let timestamp: Date
		var baselineHeartRate: Double?
	}

	public private(set) var configuration: Configuration
	public private(set) var hasPendingGesture = false

	private var recentHeartRates: [(timestamp: Date, bpm: Double)] = []
	private var pendingGesture: PendingGesture?
	private var lastCandidateAt: Date?

	public init(configuration: Configuration = .init()) {
		self.configuration = configuration
	}

	public mutating func updateSensitivity(_ sensitivity: Double) {
		let clamped = max(0, min(1, sensitivity))
		let minimumSpike = 6.0
		let maximumSpike = 16.0
		configuration.heartRateSpikeBPM = maximumSpike - (maximumSpike - minimumSpike) * clamped
	}

	/// Records a motion gesture. A candidate cannot be emitted until later HR samples arrive.
	public mutating func recordGesture(at timestamp: Date) {
		expirePendingGesture(ifNeededAt: timestamp)
		guard pendingGesture == nil else { return }
		if let lastCandidateAt,
		   timestamp.timeIntervalSince(lastCandidateAt) < configuration.detectionCooldownSeconds {
			return
		}

		pendingGesture = PendingGesture(
			timestamp: timestamp,
			baselineHeartRate: baselineHeartRate(forGestureAt: timestamp)
		)
		hasPendingGesture = true
	}

	/// Records a sample and returns a candidate once the post-gesture evidence is sufficient.
	public mutating func recordHeartRate(_ bpm: Double, at timestamp: Date) -> DetectionCandidate? {
		guard bpm.isFinite, bpm > 0 else { return nil }

		recentHeartRates.append((timestamp, bpm))
		recentHeartRates.sort { $0.timestamp < $1.timestamp }
		let retention = max(120, configuration.fusionWindowSeconds * 2)
		let cutoff = timestamp.addingTimeInterval(-retention)
		recentHeartRates.removeAll { $0.timestamp < cutoff }

		guard var pendingGesture else { return nil }
		if pendingGesture.baselineHeartRate == nil {
			pendingGesture.baselineHeartRate = baselineHeartRate(forGestureAt: pendingGesture.timestamp)
			self.pendingGesture = pendingGesture
		}
		guard timestamp > pendingGesture.timestamp else { return nil }

		let windowEnd = pendingGesture.timestamp.addingTimeInterval(configuration.fusionWindowSeconds)
		guard timestamp <= windowEnd else {
			clearPendingGesture()
			return nil
		}

		let postGestureSamples = recentHeartRates.filter {
			$0.timestamp > pendingGesture.timestamp && $0.timestamp <= windowEnd
		}
		guard let baselineHeartRate = pendingGesture.baselineHeartRate,
		      postGestureSamples.count >= configuration.minimumPostGestureSamples,
		      let peak = postGestureSamples.map(\.bpm).max(),
		      peak - baselineHeartRate >= configuration.heartRateSpikeBPM else {
			return nil
		}

		let candidate = DetectionCandidate(
			gestureAt: pendingGesture.timestamp,
			detectedAt: timestamp,
			baselineHeartRate: baselineHeartRate,
			peakHeartRate: peak
		)
		lastCandidateAt = timestamp
		clearPendingGesture()
		return candidate
	}

	private mutating func expirePendingGesture(ifNeededAt timestamp: Date) {
		guard let pendingGesture else { return }
		let deadline = pendingGesture.timestamp.addingTimeInterval(configuration.fusionWindowSeconds)
		if timestamp > deadline {
			clearPendingGesture()
		}
	}

	private func baselineHeartRate(forGestureAt timestamp: Date) -> Double? {
		let windowStart = timestamp.addingTimeInterval(-configuration.fusionWindowSeconds)
		let baselineSamples = recentHeartRates
			.filter { $0.timestamp >= windowStart && $0.timestamp <= timestamp }
			.suffix(3)
		guard baselineSamples.isEmpty == false else { return nil }
		let total = baselineSamples.reduce(0) { $0 + $1.bpm }
		return total / Double(baselineSamples.count)
	}

	private mutating func clearPendingGesture() {
		pendingGesture = nil
		hasPendingGesture = false
	}
}
