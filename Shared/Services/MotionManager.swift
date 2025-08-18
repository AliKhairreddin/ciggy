import Foundation
import CoreMotion
import Combine

/// Streams device motion and emits simple hand-to-mouth gesture detections.
/// This is a naive threshold-based classifier intended as a starting point.
public final class MotionManager: ObservableObject, Sendable {
	public static let shared = MotionManager()

	private let motionManager = CMMotionManager()
	private let queue = OperationQueue()

	@Published public private(set) var latestPitch: Double = 0 // radians
	@Published public private(set) var latestRoll: Double = 0 // radians

	/// Emits when a gesture likely resembling hand-to-mouth is detected
	public let gestureDetected = PassthroughSubject<Date, Never>()

	/// Detection tuning
	public var pitchThreshold: Double = .pi / 6 // ~30 degrees
	public var rollThreshold: Double = .pi / 5 // ~36 degrees
	public var repetitionWindow: TimeInterval = 6 // seconds to see a couple of peaks
	public var minimumPeaks: Int = 2

	private var peakTimestamps: [Date] = []

	private init() {
		queue.qualityOfService = .userInitiated
	}

	/// Starts device motion updates and internal detection
	public func start() {
		guard motionManager.isDeviceMotionAvailable else { return }
		motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
		motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
			guard let self else { return }
			guard let motion else { return }
			let attitude = motion.attitude
			let pitch = attitude.pitch
			let roll = attitude.roll
			DispatchQueue.main.async {
				self.latestPitch = pitch
				self.latestRoll = roll
			}
			self.processSample(pitch: pitch, roll: roll, timestamp: Date())
		}
	}

	public func stop() {
		motionManager.stopDeviceMotionUpdates()
	}

	private func processSample(pitch: Double, roll: Double, timestamp: Date) {
		// Very naive heuristic: when both pitch and roll cross thresholds repeatedly in a short window
		if abs(pitch) > pitchThreshold && abs(roll) > rollThreshold {
			peakTimestamps.append(timestamp)
			// drop old peaks
			peakTimestamps = peakTimestamps.filter { timestamp.timeIntervalSince($0) <= repetitionWindow }
			if peakTimestamps.count >= minimumPeaks {
				peakTimestamps.removeAll()
				DispatchQueue.main.async { self.gestureDetected.send(Date()) }
			}
		}
	}
}


