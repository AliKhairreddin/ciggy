import Combine
import Foundation

/// Connects live motion and optional heart-rate context to the session engine.
@MainActor
public final class DetectionAlgorithm: ObservableObject {
	public typealias Configuration = DetectionFusionEngine.Configuration

	/// Emits an unconfirmed motion-pattern candidate. Callers must ask the user
	/// before storing an event.
	public let candidatePublisher = PassthroughSubject<DetectionCandidate, Never>()

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
					guard let self,
					      let candidate = self.engine.recordGesture(at: timestamp) else { return }
					self.candidatePublisher.send(candidate)
				}
			}
			.store(in: &cancellables)
	}
}
