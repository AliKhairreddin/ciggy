import Foundation
import Combine

/// User-configurable settings for detection and goals
public struct UserSettings: Codable, Equatable, Sendable {
	public var quitDate: Date?
	public var dailyLimit: Int
	public var sensitivity: Double // 0.0 (low) ... 1.0 (high)
	public var notificationsEnabled: Bool

	public init(
		quitDate: Date? = nil,
		dailyLimit: Int = 10,
		sensitivity: Double = 0.5,
		notificationsEnabled: Bool = true
	) {
		self.quitDate = quitDate
		self.dailyLimit = dailyLimit
		self.sensitivity = sensitivity
		self.notificationsEnabled = notificationsEnabled
	}
}

/// Observable store that persists settings in UserDefaults
public final class UserSettingsStore: ObservableObject, Sendable {
	@Published public var settings: UserSettings {
		didSet { save() }
	}

	private let storageKey = "UserSettingsStore.settings.v1"

	public init() {
		if let data = UserDefaults.standard.data(forKey: storageKey),
		   let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
			self.settings = decoded
		} else {
			self.settings = UserSettings()
		}
	}

	private func save() {
		if let data = try? JSONEncoder().encode(settings) {
			UserDefaults.standard.set(data, forKey: storageKey)
		}
	}
}


