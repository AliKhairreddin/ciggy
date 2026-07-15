#if os(iOS)
import Combine
import Foundation
import CiggyShared

@MainActor
final class SettingsViewModel: ObservableObject {
	@Published var notificationsEnabled: Bool = false
	@Published var sensitivity: Double = 0.5
	private var cancellables = Set<AnyCancellable>()
	private var hasBound = false

	func bind(settings: UserSettingsStore) {
		guard hasBound == false else { return }
		hasBound = true
		settings.$settings
			.removeDuplicates()
			.sink { @MainActor [weak self] updatedSettings in
				self?.notificationsEnabled = updatedSettings.notificationsEnabled
				self?.sensitivity = updatedSettings.sensitivity
			}
			.store(in: &cancellables)
	}

	func save(settings: UserSettingsStore) async {
		if notificationsEnabled {
			let granted = await NotificationManager.requestAuthorization()
			notificationsEnabled = granted
		}
		var updatedSettings = settings.settings
		updatedSettings.notificationsEnabled = notificationsEnabled
		updatedSettings.sensitivity = sensitivity
		settings.settings = updatedSettings
	}
}
#endif
