#if os(iOS)
import Combine
import Foundation
import CiggyShared

@MainActor
final class GoalsViewModel: ObservableObject {
	@Published var hasQuitDate = false
	@Published var quitDate: Date? = nil
	@Published var dailyLimit: Int = 10
	private var cancellables = Set<AnyCancellable>()
	private var hasBound = false

	func bind(settings: UserSettingsStore) {
		guard hasBound == false else { return }
		hasBound = true
		// Sync each field independently. A Watch sensitivity or notification update
		// must not discard a goal the user is still editing on this iPhone.
		settings.$settings.map(\.quitDate)
			.removeDuplicates()
			.sink { @MainActor [weak self] quitDate in
				self?.hasQuitDate = quitDate != nil
				self?.quitDate = quitDate
			}
			.store(in: &cancellables)
		settings.$settings.map(\.dailyLimit)
			.removeDuplicates()
			.sink { @MainActor [weak self] dailyLimit in
				self?.dailyLimit = dailyLimit
			}
			.store(in: &cancellables)
	}

	func save(settings: UserSettingsStore) {
		var updatedSettings = settings.settings
		updatedSettings.quitDate = hasQuitDate ? (quitDate ?? Date()) : nil
		updatedSettings.dailyLimit = max(1, dailyLimit)
		settings.settings = updatedSettings
	}
}
#endif
