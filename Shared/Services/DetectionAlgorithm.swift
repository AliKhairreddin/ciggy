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
	private let userDefaults: UserDefaults
	private let storageKey: String
	private var engine: DetectionFusionEngine

	public init(
		motion: MotionManager? = nil,
		health: HealthKitManager? = nil,
		config: Configuration = .init(),
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionAlgorithm.liveSession.v1"
	) {
		self.motion = motion ?? .shared
		self.health = health ?? .shared
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		self.engine = userDefaults.data(forKey: storageKey)
			.flatMap { try? JSONDecoder().decode(DetectionFusionEngine.self, from: $0) }
			?? DetectionFusionEngine(configuration: config)
		self.engine.expireSession(at: Date())
		self.sessionGestureCount = engine.observedGestureCount
		bind()
	}

	public func updateSensitivity(multiplier: Double) {
		engine.updateSensitivity(multiplier)
		saveSession()
	}

	public func resetSession() {
		engine.resetSession()
		sessionGestureCount = 0
		saveSession()
	}

	private func saveSession() {
		if let data = try? JSONEncoder().encode(engine) { userDefaults.set(data, forKey: storageKey) }
	}

	private func bind() {
		motion.$latestSample
			.compactMap { $0?.timestamp }
			.sink { [weak self] timestamp in
				Task { @MainActor [weak self] in
					guard let self else { return }
					self.engine.expireSession(at: timestamp)
					self.sessionGestureCount = self.engine.observedGestureCount
				}
			}
			.store(in: &cancellables)

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
					// Watch consumers synchronously persist the candidate before this
					// checkpoint. A crash between those writes may replay evidence,
					// which the repository deduplicates, rather than lose the event.
					self.saveSession()
				}
			}
			.store(in: &cancellables)
	}
}
