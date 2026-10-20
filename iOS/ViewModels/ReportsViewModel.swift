#if os(iOS)
import Foundation
import Combine
import CiggyShared
import UIKit

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
				self?.refresh(repository: repository)
			}
			.store(in: &cancellables)
		Publishers.Merge3(
			Timer.publish(every: 60, on: .main, in: .common).autoconnect().map { _ in () },
			NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).map { _ in () },
			NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).map { _ in () }
		)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in self?.refresh(repository: repository) }
			.store(in: &cancellables)
		refresh(repository: repository)
	}

	private func refresh(repository: EventRepository) {
		last7DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
		last30DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 30)
		heartRateTrend = heartRatePoints(from: repository.events)
	}

	private func heartRatePoints(from events: [SmokingEvent]) -> [(Date, Double)] {
		events.compactMap { event in
			guard let heartRate = event.heartRate, heartRate.isFinite, (1...300).contains(heartRate) else { return nil }
			return (event.timestamp, heartRate)
		}
	}
}
#endif
