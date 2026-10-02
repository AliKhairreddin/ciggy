import Foundation

/// Detects a complete rest → raise → steady hold → return cycle relative to the
/// person's resting wrist orientation. No fixed pitch/roll or wrist side is assumed.
/// This detects gesture shape, not whether the person actually holds a cigarette.
public struct MotionGestureEngine: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case seekingRest, resting, raising, holding, returning }
    public struct Configuration: Codable, Equatable, Sendable {
        public var minimumRaiseAngle: Double = 0.45
        public var returnAngle: Double = 0.25
        public var minimumRestSeconds: TimeInterval = 0.6
        public var minimumHoldSeconds: TimeInterval = 0.7
        public var maximumHoldSeconds: TimeInterval = 12
        public var maximumRaiseSeconds: TimeInterval = 5
        public var maximumCycleSeconds: TimeInterval = 20
        public var minimumReturnSeconds: TimeInterval = 0.25
        public var minimumRotationRate: Double = 0.2
        public var maximumHoldRotationRate: Double = 0.8
        public var maximumHoldAcceleration: Double = 0.3
        public var maximumSampleGap: TimeInterval = 1
        public var gestureCooldown: TimeInterval = 4
        public init() {}
    }

    public let configuration: Configuration
    public private(set) var phase: Phase = .seekingRest
    public private(set) var lastGestureAt: Date?
    private var baseline: MotionVector?
    private var restAnchor: MotionVector?
    private var stableSince: Date?
    private var cycleStartedAt: Date?
    private var holdStartedAt: Date?
    private var previousSample: MotionSample?
    private var observedRotation = false
    private var hasValidHold = false

    public init(configuration: Configuration = .init()) { self.configuration = configuration }

    public mutating func record(_ sample: MotionSample) -> Date? {
        guard sample.isValid else { resetCycle(); return nil }
        let previous = previousSample
        if let previous {
            let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed > 0 else { return nil }
            if elapsed > configuration.maximumSampleGap { resetCycle() }
        }
        let elapsed = previous.map { sample.timestamp.timeIntervalSince($0.timestamp) } ?? 0
        let estimatedRotation = elapsed > 0 && elapsed <= configuration.maximumSampleGap
            ? (previous?.gravity.angle(to: sample.gravity) ?? 0) / elapsed : 0
        let rotation = sample.rotationRate?.magnitude ?? estimatedRotation
        let steady = rotation <= configuration.maximumHoldRotationRate &&
            sample.userAcceleration.magnitude <= configuration.maximumHoldAcceleration
        previousSample = sample

        if let cycleStartedAt,
           sample.timestamp.timeIntervalSince(cycleStartedAt) > configuration.maximumCycleSeconds {
            resetCycle()
            previousSample = sample
        }

        switch phase {
        case .seekingRest:
            guard steady else { stableSince = nil; restAnchor = nil; return nil }
            if let anchor = restAnchor, anchor.angle(to: sample.gravity) > 0.15 {
                stableSince = nil
                restAnchor = nil
            }
            if stableSince == nil { stableSince = sample.timestamp; restAnchor = sample.gravity }
            baseline = sample.gravity
            if let stableSince, sample.timestamp.timeIntervalSince(stableSince) >= configuration.minimumRestSeconds {
                phase = .resting
                self.stableSince = nil
            }
        case .resting:
            guard let baseline else { resetCycle(); return nil }
            let excursion = baseline.angle(to: sample.gravity)
            if excursion > configuration.returnAngle || rotation > configuration.minimumRotationRate {
                phase = .raising
                cycleStartedAt = sample.timestamp
                observedRotation = rotation >= configuration.minimumRotationRate
            } else if steady {
                self.baseline = baseline.blended(with: sample.gravity, weight: 0.02)
            }
            if phase == .raising, excursion >= configuration.minimumRaiseAngle, steady {
                phase = .holding; holdStartedAt = sample.timestamp
            }
        case .raising:
            guard let baseline, let cycleStartedAt else { resetCycle(); return nil }
            observedRotation = observedRotation || rotation >= configuration.minimumRotationRate
            if sample.timestamp.timeIntervalSince(cycleStartedAt) > configuration.maximumRaiseSeconds {
                resetCycle()
            } else if baseline.angle(to: sample.gravity) >= configuration.minimumRaiseAngle, steady {
                phase = .holding; holdStartedAt = sample.timestamp
            } else if baseline.angle(to: sample.gravity) <= configuration.returnAngle, steady {
                phase = .resting; self.cycleStartedAt = nil
            }
        case .holding:
            guard let baseline, let holdStartedAt else { resetCycle(); return nil }
            let holdDuration = sample.timestamp.timeIntervalSince(holdStartedAt)
            if holdDuration > configuration.maximumHoldSeconds { resetCycle(); return nil }
            if baseline.angle(to: sample.gravity) < configuration.minimumRaiseAngle || steady == false {
                guard hasValidHold else { phase = .raising; self.holdStartedAt = nil; return nil }
                phase = .returning
                stableSince = nil
            } else if holdDuration >= configuration.minimumHoldSeconds {
                hasValidHold = true
            }
        case .returning:
            guard let baseline else { resetCycle(); return nil }
            if baseline.angle(to: sample.gravity) <= configuration.returnAngle, steady {
                if stableSince == nil { stableSince = sample.timestamp }
                guard let stableSince,
                      sample.timestamp.timeIntervalSince(stableSince) >= configuration.minimumReturnSeconds else { return nil }
                let valid = hasValidHold && observedRotation &&
                    (lastGestureAt.map { sample.timestamp.timeIntervalSince($0) >= configuration.gestureCooldown } ?? true)
                phase = .resting
                cycleStartedAt = nil; self.holdStartedAt = nil; self.stableSince = nil
                hasValidHold = false; observedRotation = false
                if valid { lastGestureAt = sample.timestamp; return sample.timestamp }
            } else { stableSince = nil }
        }
        return nil
    }

    public mutating func reset() { resetCycle(); lastGestureAt = nil; previousSample = nil }
    private mutating func resetCycle() {
        phase = .seekingRest
        baseline = nil; restAnchor = nil; stableSince = nil; cycleStartedAt = nil
        holdStartedAt = nil; observedRotation = false; hasValidHold = false
    }
}
