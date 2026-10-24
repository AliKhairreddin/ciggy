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
			.combineLatest(Timer.publish(every: 30, on: .main, in: .common).autoconnect().prepend(Date()))
			.receive(on: DispatchQueue.main)
			.sink { [weak self] events, _ in
				guard let self else { return }
				// The timer is only a refresh trigger. Its cached timestamp can precede
				// a newly logged event, so evaluate every emission at the current time.
				let now = Date()
				// Match iPhone/widget totals when a companion's clock is ahead.
				let snapshot = LiveActivitySnapshot(events: events, dailyLimit: 1, now: now)
				self.todayCount = snapshot.dailyCount
				if let last = snapshot.lastLoggedAt {
					self.timeSinceLast = last.shortRelativeDescription(to: now)
				} else {
					self.timeSinceLast = "—"
				}
			}
			.store(in: &cancellables)
	}
}
#endif
