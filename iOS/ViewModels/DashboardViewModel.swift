import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
	@Published var dailyCount: Int = 0
	@Published var weeklyCount: Int = 0
	@Published var monthlyCount: Int = 0
	@Published var streakDays: Int = 0
	@Published var moneySaved: Double = 0
	@Published var todayProgress: Double = 0 // 0...1 of daily limit
	@Published var lastEventDescription: String = "No events yet"

	private var cancellables = Set<AnyCancellable>()

	func bind(repository: EventRepository, settings: UserSettingsStore) {
		repository.$events
			.combineLatest(settings.$settings)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _, _ in
				self?.recompute(repository: repository, settings: settings)
			}
			.store(in: &cancellables)
		recompute(repository: repository, settings: settings)
	}

	private func recompute(repository: EventRepository, settings: UserSettingsStore) {
		let now = Date()
		let calendar = Calendar.current
		let startOfToday = now.startOfDayInCurrentCalendar
		let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? startOfToday
		let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday

		dailyCount = repository.events.filter { $0.timestamp >= startOfToday }.count
		weeklyCount = repository.events.filter { $0.timestamp >= startOfWeek }.count
		monthlyCount = repository.events.filter { $0.timestamp >= startOfMonth }.count
		streakDays = repository.streakSmokeFreeDays()
		moneySaved = repository.estimatedMoneySaved()
		let limit = max(1, settings.settings.dailyLimit)
		todayProgress = min(1.0, Double(dailyCount) / Double(limit))
		if let last = repository.events.last {
			lastEventDescription = last.timestamp.shortRelativeDescription()
		} else {
			lastEventDescription = "No events yet"
		}
	}
}


