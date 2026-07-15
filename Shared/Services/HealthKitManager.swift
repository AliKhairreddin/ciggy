import Foundation
import HealthKit
import Combine

public struct HeartRateReading: Equatable, Sendable {
	public let timestamp: Date
	public let beatsPerMinute: Double

	public init(timestamp: Date, beatsPerMinute: Double) {
		self.timestamp = timestamp
		self.beatsPerMinute = beatsPerMinute
	}
}

/// Handles HealthKit authorization and observes saved heart-rate updates while the app runs.
@MainActor
public final class HealthKitManager: ObservableObject {
	public static let shared = HealthKitManager()

	private let healthStore = HKHealthStore()
	@Published public private(set) var isAuthorized: Bool = false
	@Published public private(set) var currentHeartRate: Double = 0
	@Published public private(set) var isUsingSimulatedData: Bool = false

	/// Emits heart-rate values with the timestamp supplied by HealthKit.
	public let heartRatePublisher = PassthroughSubject<HeartRateReading, Never>()

	private var query: HKAnchoredObjectQuery?
	private var mockHeartRateTimer: Timer?

	private init() {}

	public func requestAuthorization() async {
		guard HKHealthStore.isHealthDataAvailable() else {
			isAuthorized = false
			return
		}
		if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
			let types: Set = [hrType]
			do {
				try await healthStore.requestAuthorization(toShare: [], read: types)
				// HealthKit deliberately does not reveal whether read access was denied. A
				// successful request means it is safe to execute the query; denied access
				// simply returns no samples.
				isAuthorized = true
			} catch {
				isAuthorized = false
			}
		}
	}

	/// Observes new saved heart-rate samples. Simulation is limited to simulator builds.
	public func startHeartRateStreaming() {
		stopMockHeartRate()
		guard HKHealthStore.isHealthDataAvailable(),
				let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
				isAuthorized else {
			#if targetEnvironment(simulator)
			startMockHeartRate()
			#endif
			return
		}

		// Seed a short baseline window. Readings retain HealthKit timestamps, so the
		// fusion engine can distinguish baseline data from post-gesture evidence.
		let predicate = HKQuery.predicateForSamples(
			withStart: Date().addingTimeInterval(-120),
			end: nil,
			options: .strictStartDate
		)
		query = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
			self?.publishHeartRates(Self.beatsPerMinute(from: samples))
		}
		query?.updateHandler = { [weak self] _, samples, _, _, _ in
			self?.publishHeartRates(Self.beatsPerMinute(from: samples))
		}
		if let query { healthStore.execute(query) }
	}

	public func stopHeartRateStreaming() {
		if let query { healthStore.stop(query) }
		query = nil
		stopMockHeartRate()
	}

	nonisolated private static func beatsPerMinute(from samples: [HKSample]?) -> [HeartRateReading] {
		guard let quantitySamples = samples as? [HKQuantitySample] else { return [] }
		let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
		return quantitySamples.map {
			HeartRateReading(
				timestamp: $0.endDate,
				beatsPerMinute: $0.quantity.doubleValue(for: unit)
			)
		}
	}

	nonisolated private func publishHeartRates(_ readings: [HeartRateReading]) {
		Task { @MainActor [weak self] in
			guard let self else { return }
			for reading in readings.sorted(by: { $0.timestamp < $1.timestamp })
			where reading.beatsPerMinute.isFinite && reading.beatsPerMinute > 0 {
				let bpm = reading.beatsPerMinute
				currentHeartRate = bpm
				heartRatePublisher.send(reading)
			}
		}
	}

	private func startMockHeartRate() {
		guard mockHeartRateTimer == nil else { return }
		isUsingSimulatedData = true
		// Emit gentle random walk around 75 BPM
		mockHeartRateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in self?.emitMockHeartRate() }
		}
	}

	private func emitMockHeartRate() {
		let delta = Double.random(in: -3...4)
		let current = currentHeartRate == 0 ? 75 : currentHeartRate
		let new = max(50, min(130, current + delta))
		currentHeartRate = new
		heartRatePublisher.send(HeartRateReading(timestamp: Date(), beatsPerMinute: new))
	}

	private func stopMockHeartRate() {
		mockHeartRateTimer?.invalidate()
		mockHeartRateTimer = nil
		isUsingSimulatedData = false
	}
}
