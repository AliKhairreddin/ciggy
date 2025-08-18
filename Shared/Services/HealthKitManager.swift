import Foundation
import HealthKit
import Combine

/// Handles HealthKit authorization and live heart rate streaming.
public final class HealthKitManager: ObservableObject, Sendable {
	public static let shared = HealthKitManager()

	private let healthStore = HKHealthStore()
	@Published public private(set) var isAuthorized: Bool = false
	@Published public private(set) var currentHeartRate: Double = 0

	/// Emits heart rate samples in BPM
	public let heartRatePublisher = PassthroughSubject<Double, Never>()

	private var query: HKAnchoredObjectQuery?

	private init() {}

	public func requestAuthorization() async {
		guard HKHealthStore.isHealthDataAvailable() else { return }
		if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
			let types: Set = [hrType]
			do {
				try await healthStore.requestAuthorization(toShare: [], read: types)
				DispatchQueue.main.async { self.isAuthorized = self.healthStore.authorizationStatus(for: hrType) == .sharingAuthorized }
			} catch {
				DispatchQueue.main.async { self.isAuthorized = false }
			}
		}
	}

	/// Starts streaming heart rate on supported devices. On simulators or if not authorized, emits mock data.
	public func startHeartRateStreaming() {
		guard HKHealthStore.isHealthDataAvailable(),
				let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
				isAuthorized else {
			startMockHeartRate()
			return
		}

		let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-60*60), end: nil, options: .strictEndDate)
		query = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
			self?.handle(samples: samples)
		}
		query?.updateHandler = { [weak self] _, samples, _, _, _ in
			self?.handle(samples: samples)
		}
		if let query { healthStore.execute(query) }
	}

	public func stopHeartRateStreaming() {
		if let query { healthStore.stop(query) }
		query = nil
	}

	private func handle(samples: [HKSample]?) {
		guard let quantitySamples = samples as? [HKQuantitySample] else { return }
		for sample in quantitySamples {
			let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
			let bpm = sample.quantity.doubleValue(for: unit)
			DispatchQueue.main.async {
				self.currentHeartRate = bpm
				self.heartRatePublisher.send(bpm)
			}
		}
	}

	private func startMockHeartRate() {
		// Emit gentle random walk around 75 BPM
		Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
			guard let self else { return }
			let delta = Double.random(in: -3...4)
			let new = max(50, min(130, (self.currentHeartRate == 0 ? 75 : self.currentHeartRate) + delta))
			self.currentHeartRate = new
			self.heartRatePublisher.send(new)
		}
	}
}


