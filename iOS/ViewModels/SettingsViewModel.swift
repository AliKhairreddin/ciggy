import Foundation
import CiggyShared

@MainActor
final class SettingsViewModel: ObservableObject {
	@Published var notificationsEnabled: Bool = true
	@Published var sensitivity: Double = 0.5

	func bind(settings: UserSettingsStore) {
		notificationsEnabled = settings.settings.notificationsEnabled
		sensitivity = settings.settings.sensitivity
	}

	func save(settings: UserSettingsStore) {
		settings.settings.notificationsEnabled = notificationsEnabled
		settings.settings.sensitivity = sensitivity
	}
}


