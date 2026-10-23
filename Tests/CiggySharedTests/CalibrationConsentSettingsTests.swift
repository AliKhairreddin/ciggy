import Foundation
import XCTest
@testable import CiggyShared

final class CalibrationConsentSettingsTests: XCTestCase {
    func testConsentRetainsExactBoundaryThroughLegacyISOTransport() throws {
        let consent = Date(timeIntervalSinceReferenceDate: 814_406_400.987654)
        let original = UserSettings(calibrationEnabledAt: consent)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let received = try decoder.decode(UserSettings.self, from: encoder.encode(original))
        XCTAssertEqual(received.calibrationEnabledAt, consent,
                       "Rounding must not share pre-consent motion or reject the first five-minute chunk.")
    }

    func testLegacySettingsRemainOptedOut() throws {
        let legacy = Data(#"{"dailyLimit":10,"sensitivity":0.5,"notificationsEnabled":false}"#.utf8)
        let settings = try JSONDecoder().decode(UserSettings.self, from: legacy)
        XCTAssertNil(settings.calibrationEnabledAt)
        XCTAssertNil(UserSettings().calibrationEnabledAt)
    }

    @MainActor
    func testConsentPersistsAndOptOutCannotReturnOnReload() throws {
        let name = "CalibrationConsentTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserSettingsStore(defaults: defaults)
        let consent = Date(timeIntervalSince1970: 1_700_000_000.125)
        store.settings.calibrationEnabledAt = consent
        XCTAssertEqual(UserSettingsStore(defaults: defaults).settings.calibrationEnabledAt, consent)
        store.settings.calibrationEnabledAt = nil
        XCTAssertNil(UserSettingsStore(defaults: defaults).settings.calibrationEnabledAt)
        store.settings.calibrationEnabledAt = consent.addingTimeInterval(60)
        XCTAssertNotEqual(UserSettingsStore(defaults: defaults).settings.calibrationEnabledAt, consent,
                          "Resuming creates a new consent boundary rather than reviving old history")
    }

    @MainActor
    func testMalformedConsentCannotEnableHistoricalSharing() throws {
        let name = "CalibrationConsentTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = UserSettings()
        settings.calibrationEnabledAt = Date(timeIntervalSinceReferenceDate: 1e100)
        defaults.set(try JSONEncoder().encode(settings), forKey: "UserSettingsStore.settings.v1")
        let store = UserSettingsStore(defaults: defaults)
        XCTAssertNil(store.settings.calibrationEnabledAt)
        store.settings.calibrationEnabledAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertNil(store.settings.calibrationEnabledAt)
        XCTAssertNil(UserSettingsStore(defaults: defaults).settings.calibrationEnabledAt)
    }
}
