import Combine
import Foundation

/// Connects live motion and optional heart-rate context to the session engine.
@MainActor
public final class DetectionAlgorithm: ObservableObject {
	public typealias Configuration = DetectionFusionEngine.Configuration

	/// Emits a motion-pattern candidate that callers can auto-log into a passive summary.
	public let candidatePublisher = PassthroughSubject<DetectionCandidate, Never>()
	@Published public private(set) var sessionGestureCount = 0

	private var cancellables = Set<AnyCancellable>()
	private let motion: MotionManager
	private let health: HealthKitManager
	private var engine: DetectionFusionEngine

	public init(
		motion: MotionManager? = nil,
		health: HealthKitManager? = nil,
		config: Configuration = .init()
	) {
		self.motion = motion ?? .shared
		self.health = health ?? .shared
		self.engine = DetectionFusionEngine(configuration: config)
		bind()
	}

	public func updateSensitivity(multiplier: Double) {
		engine.updateSensitivity(multiplier)
	}

	public func resetSession() {
		engine.resetSession()
		sessionGestureCount = 0
	}

	private func bind() {
		health.heartRatePublisher
			.sink { [weak self] reading in
				Task { @MainActor [weak self] in
					self?.engine.recordHeartRate(reading.beatsPerMinute, at: reading.timestamp)
				}
			}
			.store(in: &cancellables)

		motion.gestureDetected
			.sink { [weak self] timestamp in
				Task { @MainActor [weak self] in
					guard let self else { return }
					let candidate = self.engine.recordGesture(at: timestamp)
					self.sessionGestureCount = self.engine.observedGestureCount
					if let candidate { self.candidatePublisher.send(candidate) }
				}
			}
			.store(in: &cancellables)
	}
}
