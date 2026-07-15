import Foundation

/// Pure threshold-edge detector used by MotionManager and its unit tests.
public struct MotionGestureEngine: Sendable {
	public var pitchThreshold: Double
	public var rollThreshold: Double
	public var repetitionWindow: TimeInterval
	public var minimumPeaks: Int
	public var minimumPeakSeparation: TimeInterval
	public var gestureCooldown: TimeInterval

	private var peakTimestamps: [Date] = []
	private var isAboveThreshold = false
	private var lastPeakAt: Date?
	private var lastGestureAt: Date?

	public init(
		pitchThreshold: Double = .pi / 6,
		rollThreshold: Double = .pi / 5,
		repetitionWindow: TimeInterval = 6,
		minimumPeaks: Int = 2,
		minimumPeakSeparation: TimeInterval = 0.5,
		gestureCooldown: TimeInterval = 8
	) {
		self.pitchThreshold = max(0, pitchThreshold)
		self.rollThreshold = max(0, rollThreshold)
		self.repetitionWindow = max(0.1, repetitionWindow)
		self.minimumPeaks = max(1, minimumPeaks)
		self.minimumPeakSeparation = max(0, minimumPeakSeparation)
		self.gestureCooldown = max(0, gestureCooldown)
	}

	/// Returns the gesture time only after distinct rising threshold edges.
	public mutating func record(pitch: Double, roll: Double, at timestamp: Date) -> Date? {
		let exceedsThreshold = abs(pitch) > pitchThreshold && abs(roll) > rollThreshold
		guard exceedsThreshold else {
			isAboveThreshold = false
			return nil
		}

		guard isAboveThreshold == false else { return nil }
		isAboveThreshold = true
		if let lastPeakAt, timestamp.timeIntervalSince(lastPeakAt) < minimumPeakSeparation { return nil }
		lastPeakAt = timestamp
		peakTimestamps.append(timestamp)
		peakTimestamps.removeAll { timestamp.timeIntervalSince($0) > repetitionWindow }

		guard peakTimestamps.count >= minimumPeaks else { return nil }
		peakTimestamps.removeAll()
		if let lastGestureAt, timestamp.timeIntervalSince(lastGestureAt) < gestureCooldown { return nil }
		lastGestureAt = timestamp
		return timestamp
	}

	public mutating func reset() {
		peakTimestamps.removeAll()
		isAboveThreshold = false
		lastPeakAt = nil
		lastGestureAt = nil
	}
}
