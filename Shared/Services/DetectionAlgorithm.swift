import Combine
import Foundation

/// Connects live motion and optional heart-rate context to the session engine.
@MainActor
public final class DetectionAlgorithm: ObservableObject {
	public typealias Configuration = DetectionFusionEngine.Configuration

	/// Emits a motion-pattern candidate that callers can auto-log into a passive summary.
	public let candidatePublisher = PassthroughSubject<DetectionCandidate, Never>()
	/// Production consumers must durably journal a detection before its checkpoint advances.
	public var persistCandidate: ((DetectionCandidate) -> Bool)?
	@Published public private(set) var sessionGestureCount = 0

	private var cancellables = Set<AnyCancellable>()
	private let motion: MotionManager
	private let health: HealthKitManager
	private let userDefaults: UserDefaults
	private let storageKey: String
	private let snapshot: DurableSnapshotFile?
	private var loadFailed = false
	@Published public private(set) var lastPersistenceError: String?
	private var engine: DetectionFusionEngine

	public init(
		motion: MotionManager? = nil,
		health: HealthKitManager? = nil,
		config: Configuration = .init(),
		userDefaults: UserDefaults = .standard,
		storageKey: String = "DetectionAlgorithm.liveSession.v1",
		snapshotURL: URL? = nil
	) {
		self.motion = motion ?? .shared
		self.health = health ?? .shared
		self.userDefaults = userDefaults
		self.storageKey = storageKey
		self.snapshot = (snapshotURL ?? (userDefaults === UserDefaults.standard ?
			DurableSnapshotFile.defaultURL(name: storageKey) : nil)).map { DurableSnapshotFile(url: $0) }
		self.engine = DetectionFusionEngine(configuration: config)
		do {
			if let data = try snapshot?.load() {
				self.engine = try JSONDecoder().decode(DetectionFusionEngine.self, from: data)
			} else if let data = userDefaults.data(forKey: storageKey) {
				self.engine = try JSONDecoder().decode(DetectionFusionEngine.self, from: data)
			}
		} catch {
			loadFailed = true
			lastPersistenceError = "Could not read saved detection progress."
		}
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

	@discardableResult private func saveSession() -> Bool {
		guard loadFailed == false else { return false }
		do {
			let data = try JSONEncoder().encode(engine)
			if let snapshot { try snapshot.write(data) } else { userDefaults.set(data, forKey: storageKey) }
			lastPersistenceError = nil
			return true
		} catch {
			lastPersistenceError = "Could not save detection progress."
			return false
		}
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
					guard let self, self.loadFailed == false else { return }
					let previous = self.engine
					let candidate = self.engine.recordGesture(at: timestamp)
					if let candidate, self.persistCandidate?(candidate) == false {
						self.engine = previous
						self.sessionGestureCount = self.engine.observedGestureCount
						return
					}
					self.sessionGestureCount = self.engine.observedGestureCount
					if let candidate { self.candidatePublisher.send(candidate) }
					// Watch consumers synchronously persist the candidate before this
					// checkpoint. A crash between those writes may replay evidence,
					// which the repository deduplicates, rather than lose the event.
					if self.saveSession() == false {
						self.engine = previous
						self.sessionGestureCount = self.engine.observedGestureCount
					}
				}
			}
			.store(in: &cancellables)
	}
}
