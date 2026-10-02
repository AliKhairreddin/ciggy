import Foundation
import Combine
import OSLog
#if os(iOS) || os(watchOS)
import CoreMotion
#endif

public enum MotionMonitoringStatus: String, Sendable {
    case stopped, starting, running, unavailable, permissionDenied, failed
}

/// Streams fused accelerometer/gyroscope data. Monitoring becomes active only
/// after the first real sample, not merely after requesting the sensor service.
@MainActor
public final class MotionManager: ObservableObject {
    public static let shared = MotionManager()
    @Published public private(set) var latestPitch: Double = 0
    @Published public private(set) var latestRoll: Double = 0
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var status: MotionMonitoringStatus = .stopped
    @Published public private(set) var lastError: String?
    @Published public private(set) var latestSample: MotionSample?
    @Published public private(set) var gesturePhase: MotionGestureEngine.Phase = .seekingRest
    @Published public private(set) var observedGestureCount = 0
    @Published public private(set) var hasGyroscope = false
    public let gestureDetected = PassthroughSubject<Date, Never>()
    public let samplePublisher = PassthroughSubject<MotionSample, Never>()

    private var gestureEngine = MotionGestureEngine()
    private var generation = UUID()
    private var startupTimeout: Task<Void, Never>?
    private var lastPublishedAt: Date?
    private let logger = Logger(subsystem: "com.ciggy.motion", category: "Sensors")
    #if os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    #endif

    private init() {
        #if os(iOS) || os(watchOS)
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        #endif
    }

    /// Allows a calibration/settings flow to tune the gesture shape separately
    /// from the number of gestures required for a smoking-session candidate.
    public func configureGestureDetection(_ configuration: MotionGestureEngine.Configuration) {
        gestureEngine = MotionGestureEngine(configuration: configuration)
        gesturePhase = .seekingRest
    }

    public func start() {
        #if os(iOS) || os(watchOS)
        guard status != .starting, isMonitoring == false else { return }
        guard motionManager.isDeviceMotionAvailable else {
            status = .unavailable
            lastError = "Device motion is unavailable on this device. Use a physical Apple Watch for detection."
            return
        }
        let authorization = CMSensorRecorder.authorizationStatus()
        guard authorization != .denied, authorization != .restricted else {
            status = .permissionDenied
            lastError = "Enable Motion & Fitness access for Ciggy in Settings."
            return
        }
        gestureEngine.reset()
        observedGestureCount = 0
        lastPublishedAt = nil
        latestSample = nil
        lastError = nil
        hasGyroscope = motionManager.isGyroAvailable
        status = .starting
        generation = UUID()
        let currentGeneration = generation
        // CMDeviceMotion timestamps are seconds since boot, not callback arrival
        // time. Preserve spacing even if delivery is delayed or queued.
        let bootDate = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            let errorMessage = error?.localizedDescription
            let sample = motion.map {
                MotionSample(
                    timestamp: bootDate.addingTimeInterval($0.timestamp),
                    gravity: .init(x: $0.gravity.x, y: $0.gravity.y, z: $0.gravity.z),
                    userAcceleration: .init(x: $0.userAcceleration.x, y: $0.userAcceleration.y, z: $0.userAcceleration.z),
                    rotationRate: .init(x: $0.rotationRate.x, y: $0.rotationRate.y, z: $0.rotationRate.z)
                )
            }
            let pitch = motion?.attitude.pitch ?? 0
            let roll = motion?.attitude.roll ?? 0
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                if let errorMessage { self.fail(errorMessage); return }
                guard let sample else { return }
                self.process(sample, pitch: pitch, roll: roll)
            }
        }
        startupTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard Task.isCancelled == false, let self,
                  self.generation == currentGeneration, self.status == .starting else { return }
            self.fail("No motion samples arrived. Check Motion & Fitness access and reopen Ciggy.")
        }
        #else
        status = .unavailable
        lastError = "Live detection requires an iPhone or Apple Watch."
        #endif
    }

    public func stop() {
        generation = UUID()
        startupTimeout?.cancel()
        startupTimeout = nil
        #if os(iOS) || os(watchOS)
        motionManager.stopDeviceMotionUpdates()
        #endif
        gestureEngine.reset()
        gesturePhase = .seekingRest
        isMonitoring = false
        status = .stopped
        MotionRecordingStore.shared.finishIfRecording()
    }

    private func fail(_ message: String) {
        stop()
        #if os(iOS) || os(watchOS)
        let authorization = CMSensorRecorder.authorizationStatus()
        status = authorization == .denied || authorization == .restricted ? .permissionDenied : .failed
        #else
        status = .failed
        #endif
        lastError = message
        logger.error("Motion stopped: \(message, privacy: .public)")
    }

    private func process(_ sample: MotionSample, pitch: Double, roll: Double) {
        guard sample.isValid else { return }
        if isMonitoring == false {
            startupTimeout?.cancel()
            startupTimeout = nil
            isMonitoring = true
            status = .running
            logger.info("Receiving device motion with fused rotation rate")
        }
        MotionRecordingStore.shared.append(sample)
        samplePublisher.send(sample)
        if let gestureAt = gestureEngine.record(sample) {
            observedGestureCount += 1
            gestureDetected.send(gestureAt)
            logger.info("Completed hand-to-mouth cycle \(self.observedGestureCount)")
        }
        // Publish UI diagnostics at 5 Hz while keeping detection at 30 Hz.
        if lastPublishedAt.map({ sample.timestamp.timeIntervalSince($0) >= 0.2 }) ?? true {
            latestPitch = pitch
            latestRoll = roll
            latestSample = sample
            gesturePhase = gestureEngine.phase
            lastPublishedAt = sample.timestamp
        }
    }
}
