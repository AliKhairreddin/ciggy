import Foundation

/// Core Motion vectors use g for acceleration and radians/second for rotation.
public struct MotionVector: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double
    public init(x: Double, y: Double, z: Double) {
        self.x = x; self.y = y; self.z = z
    }
    public var magnitude: Double { sqrt(x * x + y * y + z * z) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public var normalized: Self? {
        guard isFinite, magnitude > 0.01 else { return nil }
        return .init(x: x / magnitude, y: y / magnitude, z: z / magnitude)
    }
    public func angle(to other: Self) -> Double {
        guard let a = normalized, let b = other.normalized else { return .pi }
        return acos(max(-1, min(1, a.x * b.x + a.y * b.y + a.z * b.z)))
    }
    public func blended(with other: Self, weight: Double) -> Self {
        .init(x: x + weight * (other.x - x), y: y + weight * (other.y - y), z: z + weight * (other.z - z))
    }
}

/// A replayable sample. Historical accelerometer data has no gyroscope.
public struct MotionSample: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case liveDeviceMotion, recordedAccelerometer }
    public let timestamp: Date
    public let gravity: MotionVector
    public let userAcceleration: MotionVector
    public let rotationRate: MotionVector?
    public let source: Source
    public init(timestamp: Date, gravity: MotionVector, userAcceleration: MotionVector,
                rotationRate: MotionVector?, source: Source = .liveDeviceMotion) {
        self.timestamp = timestamp
        self.gravity = gravity
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.source = source
    }
    public var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && gravity.normalized != nil &&
        userAcceleration.isFinite && (rotationRate?.isFinite ?? true)
    }
}
