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

	/// Saved HealthKit samples are optional context, not a continuous measurement.
	/// Never attach an old or future reading to a new manual log.
	public func currentValue(at now: Date = Date(), maximumAge: TimeInterval = 120) -> Double? {
		let age = now.timeIntervalSince(timestamp)
		guard beatsPerMinute.isFinite, (1...300).contains(beatsPerMinute),
		      age.isFinite, maximumAge.isFinite, maximumAge >= 0,
		      age >= 0, age <= maximumAge else { return nil }
		return beatsPerMinute
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
	private var freshnessTimer: Timer?
	private var latestReading: HeartRateReading?
	private var streamGeneration = UUID()

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
		guard query == nil else { return }
		stopMockHeartRate()
		streamGeneration = UUID()
		let generation = streamGeneration
		latestReading = nil
		currentHeartRate = 0
		guard HKHealthStore.isHealthDataAvailable(),
				let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
				isAuthorized else {
			#if targetEnvironment(simulator)
			startMockHeartRate()
			#endif
			return
		}

		// Seed a short context window. Readings retain HealthKit timestamps so they
		// can be attached to a motion-created candidate when available.
		let predicate = HKQuery.predicateForSamples(
			withStart: Date().addingTimeInterval(-120),
			end: nil,
			options: .strictStartDate
		)
		query = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
			self?.publishHeartRates(Self.beatsPerMinute(from: samples), generation: generation)
		}
		query?.updateHandler = { [weak self] _, samples, _, _, _ in
			self?.publishHeartRates(Self.beatsPerMinute(from: samples), generation: generation)
		}
		if let query { healthStore.execute(query) }
		freshnessTimer?.invalidate()
		freshnessTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self, self.streamGeneration == generation else { return }
				self.currentHeartRate = self.freshHeartRate() ?? 0
			}
		}
	}

	public func stopHeartRateStreaming() {
		// Ignore query callbacks that were already queued before stop/restart.
		streamGeneration = UUID()
		if let query { healthStore.stop(query) }
		query = nil
		stopMockHeartRate()
		freshnessTimer?.invalidate()
		freshnessTimer = nil
		latestReading = nil
		currentHeartRate = 0
	}

	public func freshHeartRate(at now: Date = Date()) -> Double? {
		latestReading?.currentValue(at: now)
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

	nonisolated private func publishHeartRates(_ readings: [HeartRateReading], generation: UUID) {
		Task { @MainActor [weak self] in
			guard let self, self.streamGeneration == generation else { return }
			for reading in readings.sorted(by: { $0.timestamp < $1.timestamp })
			where reading.beatsPerMinute.isFinite && reading.beatsPerMinute > 0 {
				if reading.currentValue() != nil,
				   latestReading.map({ reading.timestamp >= $0.timestamp }) ?? true {
					latestReading = reading
				}
				heartRatePublisher.send(reading)
			}
			currentHeartRate = freshHeartRate() ?? 0
		}
	}

	private func startMockHeartRate() {
		guard mockHeartRateTimer == nil else { return }
		isUsingSimulatedData = true
		let generation = streamGeneration
		// Emit gentle random walk around 75 BPM
		mockHeartRateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
			Task { @MainActor [weak self] in
				guard let self, self.streamGeneration == generation else { return }
				self.emitMockHeartRate()
			}
		}
	}

	private func emitMockHeartRate() {
		let delta = Double.random(in: -3...4)
		let current = currentHeartRate == 0 ? 75 : currentHeartRate
		let new = max(50, min(130, current + delta))
		let reading = HeartRateReading(timestamp: Date(), beatsPerMinute: new)
		latestReading = reading
		currentHeartRate = new
		heartRatePublisher.send(reading)
	}

	private func stopMockHeartRate() {
		mockHeartRateTimer?.invalidate()
		mockHeartRateTimer = nil
		isUsingSimulatedData = false
	}
}
