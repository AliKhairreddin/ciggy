import Foundation
import Combine

/// Fuses motion gesture detections with heart rate spikes to confirm smoking events.
public final class DetectionAlgorithm: ObservableObject, Sendable {
	public struct Configuration: Sendable, Equatable {
		public var heartRateSpikeBPM: Double // e.g., +10 BPM within window
		public var fusionWindowSeconds: TimeInterval // seconds to correlate HR with gesture
		public init(heartRateSpikeBPM: Double = 10, fusionWindowSeconds: TimeInterval = 20) {
			self.heartRateSpikeBPM = heartRateSpikeBPM
			self.fusionWindowSeconds = fusionWindowSeconds
		}
	}

	public let eventPublisher = PassthroughSubject<SmokingEvent, Never>()

	private var cancellables = Set<AnyCancellable>()
	private var recentHeartRates: [(Date, Double)] = []
	private let motion: MotionManager
	private let health: HealthKitManager
	private var config: Configuration

	public init(motion: MotionManager = .shared, health: HealthKitManager = .shared, config: Configuration = .init()) {
		self.motion = motion
		self.health = health
		self.config = config
		bind()
	}

	public func updateSensitivity(multiplier: Double) {
		// Map 0...1 to different sensitivity levels by adjusting spike threshold
		let minSpike = 6.0
		let maxSpike = 16.0
		config.heartRateSpikeBPM = max(minSpike, min(maxSpike, maxSpike - (maxSpike - minSpike) * multiplier))
	}

	private func bind() {
		health.heartRatePublisher
			.sink { [weak self] bpm in
				self?.recentHeartRates.append((Date(), bpm))
				let cutoff = Date().addingTimeInterval(-120)
				self?.recentHeartRates = self?.recentHeartRates.filter { $0.0 >= cutoff } ?? []
			}
			.store(in: &cancellables)

		motion.gestureDetected
			.sink { [weak self] time in
				self?.evaluateGesture(at: time)
			}
			.store(in: &cancellables)
	}

	private func evaluateGesture(at time: Date) {
		// Find baseline HR before gesture and peak after within fusion window
		let windowStart = time.addingTimeInterval(-config.fusionWindowSeconds)
		let windowEnd = time.addingTimeInterval(config.fusionWindowSeconds)
		let window = recentHeartRates.filter { $0.0 >= windowStart && $0.0 <= windowEnd }
		guard window.count >= 2 else { return }
		let before = window.filter { $0.0 <= time }.map { $0.1 }
		let after = window.filter { $0.0 > time }.map { $0.1 }
		guard let baseline = before.last ?? window.first?.1, let maxAfter = after.max() ?? window.last?.1 else { return }
		if maxAfter - baseline >= config.heartRateSpikeBPM {
			let event = SmokingEvent(timestamp: Date(), source: .automatic, heartRate: maxAfter, notes: nil)
			eventPublisher.send(event)
		}
	}
}


