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
		notificationsEnabled: Bool = false
	) {
		self.quitDate = quitDate
		self.dailyLimit = Self.clampedDailyLimit(dailyLimit)
		self.sensitivity = Self.clampedSensitivity(sensitivity)
		self.notificationsEnabled = notificationsEnabled
	}

	public static func clampedDailyLimit(_ value: Int) -> Int {
		max(1, min(100, value))
	}

	public static func clampedSensitivity(_ value: Double) -> Double {
		max(0, min(1, value))
	}
}

/// Observable store that persists settings in UserDefaults
@MainActor
public final class UserSettingsStore: ObservableObject {
	@Published public var settings: UserSettings {
		didSet {
			var normalized = settings
			normalized.dailyLimit = UserSettings.clampedDailyLimit(settings.dailyLimit)
			normalized.sensitivity = UserSettings.clampedSensitivity(settings.sensitivity)
			// Mutating a member through @Published re-enters this observer.
			// Normalize a local copy instead, and replace only invalid values.
			if normalized != settings {
				settings = normalized
			}
			save()
		}
	}

	private let storageKey = "UserSettingsStore.settings.v1"
	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		if let data = defaults.data(forKey: storageKey),
		   let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
			self.settings = decoded
		} else {
			self.settings = UserSettings()
		}
	}

	private func save() {
		if let data = try? JSONEncoder().encode(settings) {
			defaults.set(data, forKey: storageKey)
		}
	}
}

