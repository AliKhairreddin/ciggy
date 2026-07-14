import Foundation
import Combine
import CiggyShared

@MainActor
final class WatchDashboardViewModel: ObservableObject {
	@Published var currentHeartRate: Double = 0
	@Published var todayCount: Int = 0
	@Published var timeSinceLast: String = "—"

	private var cancellables: Set<AnyCancellable> = []

	func bind(repository: EventRepository) {
		HealthKitManager.shared.$currentHeartRate
			.receive(on: DispatchQueue.main)
			.assign(to: &self.$currentHeartRate)

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


