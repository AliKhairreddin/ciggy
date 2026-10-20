import Foundation
import XCTest
@testable import CiggyShared

final class UserSettingsStoreTests: XCTestCase {
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
