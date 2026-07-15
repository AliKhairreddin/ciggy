import Combine
import Foundation

/// Connects live motion and heart-rate streams to the deterministic fusion engine.
@MainActor
public final class DetectionAlgorithm: ObservableObject {
	public typealias Configuration = DetectionFusionEngine.Configuration

	/// Emits an unconfirmed candidate. Callers must ask the user before storing an event.
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
					self?.recordHeartRate(reading.beatsPerMinute, at: reading.timestamp)
				}
			}
			.store(in: &cancellables)

		motion.gestureDetected
			.sink { [weak self] timestamp in
				Task { @MainActor [weak self] in
					self?.engine.recordGesture(at: timestamp)
				}
			}
			.store(in: &cancellables)
	}

	private func recordHeartRate(_ bpm: Double, at timestamp: Date) {
		if let candidate = engine.recordHeartRate(bpm, at: timestamp) {
			candidatePublisher.send(candidate)
		}
	}
}
