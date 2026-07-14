import Foundation
import CiggyShared

@MainActor
final class GoalsViewModel: ObservableObject {
	@Published var quitDate: Date? = nil
	@Published var dailyLimit: Int = 10
	@Published var reductionGoal: Int = 0

	func bind(settings: UserSettingsStore) {
		quitDate = settings.settings.quitDate
		dailyLimit = settings.settings.dailyLimit
		reductionGoal = max(0, settings.settings.dailyLimit - 2)
	}

	func save(settings: UserSettingsStore) {
		settings.settings.quitDate = quitDate
		settings.settings.dailyLimit = max(1, dailyLimit)
	}
}


