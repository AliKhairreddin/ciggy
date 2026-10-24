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
    // Optional checkpoint fields migrate analyzers written before continuity
    // proof existed. Canonical capture starts are trusted; cold replays are not.
    private var requiresBoundary: Bool?
    private var quietSince: Date?
    private var sourceDisruptions: Int?
    private var deferredCandidates: Int?

    public var sourceDisruptionCount: Int { sourceDisruptions ?? 0 }
    public var deferredCandidateCount: Int { deferredCandidates ?? 0 }
    public var hasConfirmedContinuity: Bool { requiresBoundary != true }
    public var latestProcessedSampleAt: Date? { lastSampleAt }

    public init(sensitivity: Double = 0.5, sampleInterval: TimeInterval = 0.1,
                gravityTimeConstant: TimeInterval = 0.25,
                gestureEngine: MotionGestureEngine = .init(),
                fusionConfiguration: DetectionFusionEngine.Configuration = .init(),
                requiresConfirmedBoundary: Bool = false) {
        self.sampleInterval = sampleInterval.isFinite ? min(1, max(0.02, sampleInterval)) : 0.1
        self.gravityTimeConstant = gravityTimeConstant.isFinite ? min(5, max(0.05, gravityTimeConstant)) : 0.25
        self.gestureEngine = gestureEngine
        fusionEngine = DetectionFusionEngine(configuration: fusionConfiguration)
        fusionEngine.updateSensitivity(sensitivity)
        requiresBoundary = requiresConfirmedBoundary
    }

    public mutating func updateSensitivity(_ sensitivity: Double) { fusionEngine.updateSensitivity(sensitivity) }

    /// An unavailable interval is not an observed pause between cigarettes.
    public mutating func sourceBecameUnavailable() {
        requiresBoundary = true
        quietSince = nil
        gravity = nil
        gestureEngine.reset()
        sourceDisruptions = sourceDisruptionCount &+ 1
    }

    public mutating func record(_ sample: RecordedAccelerationSample) -> DetectionCandidate? {
        let acceleration = MotionVector(x: sample.x, y: sample.y, z: sample.z)
        guard MotionHistoryProcessor.isSupportedDate(sample.timestamp) else {
            sourceBecameUnavailable()
            return nil
        }
        // Ignore old deliveries before they can interrupt the current stream.
        if let lastSampleAt, sample.timestamp <= lastSampleAt { return nil }
        guard acceleration.isFinite, acceleration.magnitude.isFinite, acceleration.magnitude > 0.01 else {
            sourceBecameUnavailable()
            lastSampleAt = sample.timestamp
            return nil
        }
        let elapsed = lastSampleAt.map { sample.timestamp.timeIntervalSince($0) } ?? sampleInterval
        guard elapsed >= sampleInterval - 0.000_001 else { return nil }
        if elapsed > gestureEngine.configuration.maximumSampleGap {
            sourceBecameUnavailable()
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
        let gestureAt = gestureEngine.record(motion)
        if quietSince == nil { quietSince = sample.timestamp }
        if let gestureAt {
            quietSince = gestureAt
            let candidate = fusionEngine.recordGesture(at: gestureAt)
            if requiresBoundary == true {
                if candidate != nil { deferredCandidates = deferredCandidateCount &+ 1 }
                return nil
            }
            return candidate
        }
        if requiresBoundary == true, let quietSince,
           sample.timestamp.timeIntervalSince(quietSince) > fusionEngine.sessionBoundarySeconds {
            requiresBoundary = false
            fusionEngine.confirmObservedSessionBoundary()
        }
        return nil
    }
}
