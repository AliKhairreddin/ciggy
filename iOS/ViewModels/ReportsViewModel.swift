import Foundation
import Combine
import CiggyShared

@MainActor
final class ReportsViewModel: ObservableObject {
	@Published var last7DayCounts: [DayCount] = []
	@Published var last30DayCounts: [DayCount] = []
	@Published var mockHeartRateTrend: [(Date, Double)] = []

	private var cancellables = Set<AnyCancellable>()

	func bind(repository: EventRepository) {
		repository.$events
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				guard let self else { return }
				self.last7DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
				self.last30DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 30)
				self.mockHeartRateTrend = self.generateMockHeartRate()
			}
			.store(in: &cancellables)
		last7DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 7)
		last30DayCounts = ChartHelpers.dayCounts(for: repository.events, lastNDays: 30)
		mockHeartRateTrend = generateMockHeartRate()
	}

	private func generateMockHeartRate() -> [(Date, Double)] {
		let now = Date()
		return (0..<48).map { i in
			let t = Calendar.current.date(byAdding: .hour, value: -i, to: now) ?? now
			let bpm = 70 + sin(Double(i) / 6.0) * 8 + Double.random(in: -3...3)
			return (t, max(50, min(130, bpm)))
		}.sorted { $0.0 < $1.0 }
	}
}


