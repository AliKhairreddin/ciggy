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
		settings.$settings
			.removeDuplicates()
			.sink { @MainActor [weak self] updatedSettings in
				self?.hasQuitDate = updatedSettings.quitDate != nil
				self?.quitDate = updatedSettings.quitDate
				self?.dailyLimit = updatedSettings.dailyLimit
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
