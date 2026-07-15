#if os(watchOS)
import Foundation
import Combine
import CiggyShared

@MainActor
final class WatchDashboardViewModel: ObservableObject {
	@Published var currentHeartRate: Double = 0
	@Published var isUsingSimulatedHeartRate = false
	@Published var isMotionMonitoring = false
	@Published var todayCount: Int = 0
	@Published var timeSinceLast: String = "—"

	private var cancellables: Set<AnyCancellable> = []
	private var hasBound = false

	func bind(repository: EventRepository) {
		guard hasBound == false else { return }
		hasBound = true

		HealthKitManager.shared.$currentHeartRate
			.receive(on: DispatchQueue.main)
			.assign(to: &self.$currentHeartRate)

		HealthKitManager.shared.$isUsingSimulatedData
			.receive(on: DispatchQueue.main)
			.assign(to: &self.$isUsingSimulatedHeartRate)

		MotionManager.shared.$isMonitoring
			.receive(on: DispatchQueue.main)
			.assign(to: &self.$isMotionMonitoring)

		repository.$events
			.receive(on: DispatchQueue.main)
			.sink { [weak self] events in
				guard let self else { return }
				self.todayCount = events.filter { Calendar.current.isDateInToday($0.timestamp) }.count
				if let last = events.last {
					self.timeSinceLast = last.timestamp.shortRelativeDescription()
				} else {
					self.timeSinceLast = "—"
				}
			}
			.store(in: &cancellables)
	}
}
#endif
