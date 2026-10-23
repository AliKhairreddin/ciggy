import Foundation
import Combine

/// User-configurable settings for detection and goals
public struct UserSettings: Codable, Equatable, Sendable {
	private enum CodingKeys: String, CodingKey {
		case quitDate, dailyLimit, sensitivity, notificationsEnabled, calibrationEnabledAt
		case calibrationConsentReferenceTime
	}
	public var quitDate: Date?
	public var dailyLimit: Int
	public var sensitivity: Double // 0.0 (low) ... 1.0 (high)
	public var notificationsEnabled: Bool
	/// Explicit opt-in on iPhone; no raw history before this instant is shared.
	public var calibrationEnabledAt: Date?

	public init(
		quitDate: Date? = nil,
		dailyLimit: Int = 10,
		sensitivity: Double = 0.5,
		notificationsEnabled: Bool = false,
		calibrationEnabledAt: Date? = nil
	) {
		self.quitDate = Self.validQuitDate(quitDate)
		self.dailyLimit = Self.clampedDailyLimit(dailyLimit)
		self.sensitivity = Self.clampedSensitivity(sensitivity)
		self.notificationsEnabled = notificationsEnabled
		self.calibrationEnabledAt = Self.validQuitDate(calibrationEnabledAt)
	}

	public static func clampedDailyLimit(_ value: Int) -> Int {
		max(1, min(100, value))
	}

	public static func clampedSensitivity(_ value: Double) -> Double {
		value.isFinite ? max(0, min(1, value)) : 0.5
	}

	static func validQuitDate(_ date: Date?) -> Date? {
		guard let date, date.timeIntervalSince1970.isFinite,
		      date >= .distantPast, date <= .distantFuture else { return nil }
		return date
	}

	public init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		let consent: Date?
		if let referenceTime = try values.decodeIfPresent(Double.self, forKey: .calibrationConsentReferenceTime) {
			consent = Date(timeIntervalSinceReferenceDate: referenceTime)
		} else {
			consent = try values.decodeIfPresent(Date.self, forKey: .calibrationEnabledAt)
		}
		self.init(
			quitDate: try values.decodeIfPresent(Date.self, forKey: .quitDate),
			dailyLimit: try values.decode(Int.self, forKey: .dailyLimit),
			sensitivity: try values.decode(Double.self, forKey: .sensitivity),
			notificationsEnabled: try values.decode(Bool.self, forKey: .notificationsEnabled),
			calibrationEnabledAt: consent
		)
	}

	public func encode(to encoder: Encoder) throws {
		var values = encoder.container(keyedBy: CodingKeys.self)
		try values.encodeIfPresent(quitDate, forKey: .quitDate)
		try values.encode(dailyLimit, forKey: .dailyLimit)
		try values.encode(sensitivity, forKey: .sensitivity)
		try values.encode(notificationsEnabled, forKey: .notificationsEnabled)
		// WatchConnectivity's legacy ISO dates lose fractions of a second. Keep
		// this consent boundary exact regardless of the enclosing date strategy.
		// Older app versions safely ignore the new key.
		try values.encodeIfPresent(calibrationEnabledAt?.timeIntervalSinceReferenceDate,
		                           forKey: .calibrationConsentReferenceTime)
	}
}

/// Observable store that persists settings in UserDefaults
@MainActor
public final class UserSettingsStore: ObservableObject {
	@Published public var settings: UserSettings {
		didSet {
			var normalized = settings
			normalized.quitDate = UserSettings.validQuitDate(settings.quitDate)
			normalized.calibrationEnabledAt = UserSettings.validQuitDate(settings.calibrationEnabledAt)
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

