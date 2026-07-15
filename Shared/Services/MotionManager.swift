import Foundation
#if os(iOS) || os(watchOS)
import CoreMotion
#endif
import Combine

#if os(iOS) || os(watchOS)
/// Streams device motion and emits simple hand-to-mouth gesture detections.
/// This is a naive threshold-based classifier intended as a starting point.
@MainActor
public final class MotionManager: ObservableObject {
	public static let shared = MotionManager()

	private let motionManager = CMMotionManager()
	private let queue = OperationQueue()

	@Published public private(set) var latestPitch: Double = 0 // radians
	@Published public private(set) var latestRoll: Double = 0 // radians
	@Published public private(set) var isMonitoring: Bool = false

	/// Emits when a gesture likely resembling hand-to-mouth is detected
	public let gestureDetected = PassthroughSubject<Date, Never>()

	private var gestureEngine = MotionGestureEngine()

	private init() {
		queue.qualityOfService = .userInitiated
	}

	/// Starts device motion updates and internal detection
	public func start() {
		guard motionManager.isDeviceMotionAvailable else {
			isMonitoring = false
			return
		}
		guard motionManager.isDeviceMotionActive == false else { return }
		motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
		motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
			guard let motion else { return }
			let pitch = motion.attitude.pitch
			let roll = motion.attitude.roll
			let timestamp = Date()
			Task { @MainActor [weak self] in
				guard let self else { return }
				self.latestPitch = pitch
				self.latestRoll = roll
				self.processSample(pitch: pitch, roll: roll, timestamp: timestamp)
			}
		}
		isMonitoring = motionManager.isDeviceMotionActive
	}

	public func stop() {
		motionManager.stopDeviceMotionUpdates()
		gestureEngine.reset()
		isMonitoring = false
	}

	private func processSample(pitch: Double, roll: Double, timestamp: Date) {
		if let gestureAt = gestureEngine.record(pitch: pitch, roll: roll, at: timestamp) {
			gestureDetected.send(gestureAt)
		}
	}
}
#else
/// Host-platform fallback used to run the deterministic shared tests on macOS.
@MainActor
public final class MotionManager: ObservableObject {
	public static let shared = MotionManager()
	@Published public private(set) var latestPitch: Double = 0
	@Published public private(set) var latestRoll: Double = 0
	@Published public private(set) var isMonitoring: Bool = false
	public let gestureDetected = PassthroughSubject<Date, Never>()

	private init() {}
	public func start() {}
	public func stop() {}
}
#endif
