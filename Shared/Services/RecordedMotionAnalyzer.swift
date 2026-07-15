import Foundation

/// A platform-neutral accelerometer sample used to analyze sensor-recorder history.
public struct RecordedAccelerationSample: Equatable, Sendable {
	public let timestamp: Date
	public let x: Double
	public let y: Double
	public let z: Double

	public init(timestamp: Date, x: Double, y: Double, z: Double) {
		self.timestamp = timestamp
		self.x = x
		self.y = y
		self.z = z
	}
}

/// Converts recorded acceleration into an approximate gravity attitude, then feeds the
/// same gesture and smoking-session engines used by live monitoring.
///
/// Historical sensor recording supplies acceleration rather than `CMDeviceMotion`, so a
/// low-pass filter estimates gravity before pitch and roll are calculated. Processing is
/// intentionally downsampled to reduce the cost of reviewing hours of 50 Hz history.
public struct RecordedMotionAnalyzer: Sendable {
	public var sampleInterval: TimeInterval
	public var gravityFilterStrength: Double

	private var gestureEngine: MotionGestureEngine
	private var fusionEngine: DetectionFusionEngine
	private var gravity: (x: Double, y: Double, z: Double)?
	private var lastSampleAt: Date?

	public init(
		sensitivity: Double = 0.5,
		sampleInterval: TimeInterval = 0.1,
		gravityFilterStrength: Double = 0.8,
		gestureEngine: MotionGestureEngine = .init(),
		fusionConfiguration: DetectionFusionEngine.Configuration = .init()
	) {
		self.sampleInterval = max(0.02, sampleInterval)
		self.gravityFilterStrength = max(0, min(0.98, gravityFilterStrength))
		self.gestureEngine = gestureEngine
		self.fusionEngine = DetectionFusionEngine(configuration: fusionConfiguration)
		self.fusionEngine.updateSensitivity(sensitivity)
	}

	/// Returns a candidate after enough separated hand-to-mouth-like raises are observed.
	public mutating func record(_ sample: RecordedAccelerationSample) -> DetectionCandidate? {
		if let lastSampleAt {
			let elapsed = sample.timestamp.timeIntervalSince(lastSampleAt)
			guard elapsed >= sampleInterval else { return nil }
			guard elapsed >= 0 else { return nil }
		}
		lastSampleAt = sample.timestamp

		if let previous = gravity {
			let retained = gravityFilterStrength
			let incoming = 1 - retained
			gravity = (
				x: retained * previous.x + incoming * sample.x,
				y: retained * previous.y + incoming * sample.y,
				z: retained * previous.z + incoming * sample.z
			)
		} else {
			gravity = (sample.x, sample.y, sample.z)
		}

		guard let gravity else { return nil }
		let pitch = atan2(-gravity.x, hypot(gravity.y, gravity.z))
		let roll = atan2(gravity.y, gravity.z)
		guard let gestureAt = gestureEngine.record(
			pitch: pitch,
			roll: roll,
			at: sample.timestamp
		) else { return nil }
		return fusionEngine.recordGesture(at: gestureAt)
	}
}
