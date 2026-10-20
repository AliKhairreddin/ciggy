import Foundation
import XCTest
@testable import CiggyShared

final class UserSettingsStoreTests: XCTestCase {
	@MainActor
	func testPersistedSettingsAreNormalizedBeforeFirstPublication() throws {
		let suite = "CiggySettingsTests.\(UUID())"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		var settings = UserSettings()
		settings.dailyLimit = -100
		settings.sensitivity = 1e100
		settings.quitDate = Date(timeIntervalSinceReferenceDate: 1e100)
		defaults.set(try JSONEncoder().encode(settings), forKey: "UserSettingsStore.settings.v1")
		let store = UserSettingsStore(defaults: defaults)
		XCTAssertEqual(store.settings.dailyLimit, 1)
		XCTAssertEqual(store.settings.sensitivity, 1)
		XCTAssertNil(store.settings.quitDate)
		store.settings.sensitivity = .nan
		store.settings.quitDate = Date(timeIntervalSinceReferenceDate: .infinity)
		XCTAssertEqual(store.settings.sensitivity, 0.5)
		XCTAssertNil(store.settings.quitDate)
		XCTAssertEqual(UserSettingsStore(defaults: defaults).settings, store.settings)
	}

	@MainActor
	func testGoalSavePersistsAcrossStoreReloadWithoutRecursion() throws {
		let suite = "CiggySettingsTests.\(UUID())"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = UserSettingsStore(defaults: defaults)
		var updated = store.settings
		updated.dailyLimit = 11
		updated.quitDate = Date(timeIntervalSince1970: 1_800_000_000)
		store.settings = updated

		XCTAssertEqual(UserSettingsStore(defaults: defaults).settings, updated)
		// Member writes are also used by notification and detection settings.
		store.settings.notificationsEnabled = true
		XCTAssertTrue(UserSettingsStore(defaults: defaults).settings.notificationsEnabled)
	}

	@MainActor
	func testInvalidIncomingSettingsAreNormalizedAndPersisted() throws {
		let suite = "CiggySettingsTests.\(UUID())"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = UserSettingsStore(defaults: defaults)
		var incoming = UserSettings(notificationsEnabled: true)
		incoming.dailyLimit = 500
		incoming.sensitivity = -2
		store.settings = incoming

		let reloaded = UserSettingsStore(defaults: defaults).settings
		XCTAssertEqual(reloaded.dailyLimit, 100)
		XCTAssertEqual(reloaded.sensitivity, 0)
		XCTAssertTrue(reloaded.notificationsEnabled)
	}
}
