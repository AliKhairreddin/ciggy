import Foundation

public struct RecordedAccelerationSample: Equatable, Sendable {
    public let timestamp: Date
    public let x: Double
    public let y: Double
    public let z: Double
    public init(timestamp: Date, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp; self.x = x; self.y = y; self.z = z
    }
}

/// Background recordings provide acceleration only. Estimate gravity using a
/// time-based filter, retain residual acceleration, and infer angular speed from
/// consecutive gravity vectors. Never fabricate gyroscope data for this path.
public struct RecordedMotionAnalyzer: Codable, Sendable {
    public let sampleInterval: TimeInterval
    public let gravityTimeConstant: TimeInterval
    private var gestureEngine: MotionGestureEngine
    private var fusionEngine: DetectionFusionEngine
    private var gravity: MotionVector?
    private var lastSampleAt: Date?

    public init(sensitivity: Double = 0.5, sampleInterval: TimeInterval = 0.1,
                gravityTimeConstant: TimeInterval = 0.25,
                gestureEngine: MotionGestureEngine = .init(),
                fusionConfiguration: DetectionFusionEngine.Configuration = .init()) {
        self.sampleInterval = max(0.02, sampleInterval)
        self.gravityTimeConstant = max(0.05, gravityTimeConstant)
        self.gestureEngine = gestureEngine
        fusionEngine = DetectionFusionEngine(configuration: fusionConfiguration)
        fusionEngine.updateSensitivity(sensitivity)
    }

    public mutating func updateSensitivity(_ sensitivity: Double) { fusionEngine.updateSensitivity(sensitivity) }

    public mutating func record(_ sample: RecordedAccelerationSample) -> DetectionCandidate? {
        let acceleration = MotionVector(x: sample.x, y: sample.y, z: sample.z)
        guard acceleration.isFinite, sample.timestamp.timeIntervalSince1970.isFinite else { return nil }
        let elapsed = lastSampleAt.map { sample.timestamp.timeIntervalSince($0) } ?? sampleInterval
        guard elapsed >= sampleInterval - 0.000_001 else { return nil }
        if elapsed > gestureEngine.configuration.maximumSampleGap {
            gravity = nil
            gestureEngine.reset()
            // The session engine keeps separated complete gestures; it resets them
            // on a long inter-gesture gap. A sensor gap cannot complete a gesture.
        }
        lastSampleAt = sample.timestamp
        let weight = 1 - exp(-elapsed / gravityTimeConstant)
        gravity = gravity?.blended(with: acceleration, weight: weight) ?? acceleration
        guard let gravity else { return nil }
        let motion = MotionSample(
            timestamp: sample.timestamp,
            gravity: gravity,
            userAcceleration: .init(x: acceleration.x - gravity.x, y: acceleration.y - gravity.y, z: acceleration.z - gravity.z),
            rotationRate: nil,
            source: .recordedAccelerometer
        )
        guard let gestureAt = gestureEngine.record(motion) else { return nil }
        return fusionEngine.recordGesture(at: gestureAt)
    }
}
