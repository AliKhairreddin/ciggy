#if os(iOS)
import Foundation
import Combine
import CiggyShared

@MainActor
final class ReportsViewModel: ObservableObject {
	@Published var last7DayCounts: [DayCount] = []
	@Published var last30DayCounts: [DayCount] = []
	@Published var heartRateTrend: [(Date, Double)] = []

	private var cancellables = Set<AnyCancellable>()
	private var hasBound = false

	func bind(repository: EventRepository) {
		guard hasBound == false else { return }
		hasBound = true
		repository.$events
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				guard let self else { return }
				self.last7DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
				self.last30DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 30)
				self.heartRateTrend = self.heartRatePoints(from: repository.events)
			}
			.store(in: &cancellables)
		last7DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
		last30DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 30)
		heartRateTrend = heartRatePoints(from: repository.events)
	}

	private func heartRatePoints(from events: [SmokingEvent]) -> [(Date, Double)] {
		events.compactMap { event in
			guard let heartRate = event.heartRate, heartRate > 0 else { return nil }
			return (event.timestamp, heartRate)
		}
	}
}
#endif
