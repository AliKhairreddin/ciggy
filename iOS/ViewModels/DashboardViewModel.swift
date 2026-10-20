#if os(iOS)
import Foundation
import Combine
import CiggyShared
import UIKit

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
	private var hasBound = false

	func bind(repository: EventRepository, settings: UserSettingsStore) {
		guard hasBound == false else { return }
		hasBound = true
		repository.$events
			.combineLatest(settings.$settings)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _, _ in
				self?.recompute(repository: repository, settings: settings)
			}
			.store(in: &cancellables)
		// Recompute calendar totals even when no event changes at midnight or while
		// the app is suspended. The timer also updates relative event descriptions.
		Publishers.Merge3(
			Timer.publish(every: 60, on: .main, in: .common).autoconnect().map { _ in () },
			NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).map { _ in () },
			NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).map { _ in () }
		)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
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

		dailyCount = repository.events.filter { $0.timestamp >= startOfToday && $0.timestamp <= now }.count
		weeklyCount = repository.events.filter { $0.timestamp >= startOfWeek && $0.timestamp <= now }.count
		monthlyCount = repository.events.filter { $0.timestamp >= startOfMonth && $0.timestamp <= now }.count
		streakDays = repository.streakSmokeFreeDays()
		moneySaved = repository.estimatedMoneySaved()
		let limit = max(1, settings.settings.dailyLimit)
		todayProgress = min(1.0, Double(dailyCount) / Double(limit))
		if let last = repository.events.last(where: { $0.timestamp <= now }) {
			lastEventDescription = last.timestamp.shortRelativeDescription()
		} else {
			lastEventDescription = "No events yet"
		}
	}
}
#endif
