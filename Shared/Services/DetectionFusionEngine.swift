import Foundation
import CryptoKit

/// Groups repeated hand-to-mouth gestures into one probable smoking session.
///
/// Motion is the primary signal. Heart-rate samples are retained only to attach
/// optional context to the candidate and are never required for detection.
public struct DetectionFusionEngine: Codable, Sendable {
	public struct Configuration: Codable, Sendable, Equatable {
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

	private struct HeartRateContext: Codable, Sendable {
		let timestamp: Date
		let bpm: Double
	}
	private var recentHeartRates: [HeartRateContext] = []
	private var gestureTimestamps: [Date] = []
	private var lastCandidateAt: Date?

	public init(configuration: Configuration = .init()) {
		self.configuration = configuration
	}

	/// Higher sensitivity asks for fewer repeated movements; it never changes
	/// the core requirement that multiple separated raise/lower cycles occur.
	public mutating func updateSensitivity(_ sensitivity: Double) {
		let clamped = sensitivity.isFinite ? max(0, min(1, sensitivity)) : 0.5
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
		recentHeartRates.append(.init(timestamp: timestamp, bpm: bpm))
		recentHeartRates.sort { $0.timestamp < $1.timestamp }
		trimHeartRates(relativeTo: timestamp)
	}

	/// Records a distinct hand-to-mouth gesture and emits once the motion pattern
	/// reaches the configured count inside a cigarette-sized time window.
	public mutating func recordGesture(at timestamp: Date) -> DetectionCandidate? {
		guard timestamp.timeIntervalSince1970.isFinite,
		      abs(timestamp.timeIntervalSince1970) < Double(Int64.max) / 1_000 else { return nil }
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
			id: Self.candidateID(at: timestamp),
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

	/// Clears an interrupted session while preserving the cooldown of a logged event.
	public mutating func resetSession() {
		gestureTimestamps.removeAll()
		recentHeartRates.removeAll()
	}

	/// Reprocessing the same sensor window after termination must emit the same event
	/// ID, including when the previous event has a deletion tombstone.
	private static func candidateID(at timestamp: Date) -> UUID {
		let key = "ciggy-motion-v2:\(Int64(timestamp.timeIntervalSince1970 * 1_000))"
		var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
		bytes[6] = (bytes[6] & 0x0f) | 0x50
		bytes[8] = (bytes[8] & 0x3f) | 0x80
		return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
		                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
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
