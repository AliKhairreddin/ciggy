//
//  ciggyTests.swift
//  ciggyTests
//
//  Created by Ali Khairreddin on 2026-07-14.
//

import Foundation
import CiggyShared
import Testing
@testable import ciggy

@MainActor
struct ciggyTests {
    @Test func unrelatedWatchSettingsDoNotDiscardGoalDraft() async {
        await withSettings { settings in
            let model = GoalsViewModel()
            model.bind(settings: settings)
            let target = Date(timeIntervalSince1970: 2_000_000_000)
            model.dailyLimit = 6
            model.hasQuitDate = true
            model.quitDate = target

            settings.settings.sensitivity = 0.8
            settings.settings.notificationsEnabled = true
            settings.settings.calibrationEnabledAt = Date()

            #expect(model.dailyLimit == 6)
            #expect(model.hasQuitDate)
            #expect(model.quitDate == target)
            model.save(settings: settings)
            #expect(settings.settings.dailyLimit == 6)
            #expect(settings.settings.quitDate == target)
            #expect(settings.settings.sensitivity == 0.8)
            #expect(settings.settings.notificationsEnabled)
            #expect(settings.settings.calibrationEnabledAt != nil)
        }
    }

    @Test func syncedGoalFieldsRefreshIndependently() async {
        await withSettings { settings in
            let model = GoalsViewModel()
            model.bind(settings: settings)
            let draftDate = Date(timeIntervalSince1970: 2_000_000_000)
            model.hasQuitDate = true
            model.quitDate = draftDate

            settings.settings.dailyLimit = 4

            #expect(model.dailyLimit == 4)
            #expect(model.hasQuitDate)
            #expect(model.quitDate == draftDate)

            model.dailyLimit = 7
            let remoteDate = draftDate.addingTimeInterval(86_400)
            settings.settings.quitDate = remoteDate

            #expect(model.dailyLimit == 7)
            #expect(model.quitDate == remoteDate)
        }
    }

    @Test func unrelatedGoalAndConsentUpdatesDoNotDiscardSettingsDraft() async {
        await withSettings { settings in
            let model = SettingsViewModel()
            model.bind(settings: settings)
            model.sensitivity = 0.9
            model.notificationsEnabled = true

            settings.settings.dailyLimit = 4
            settings.settings.quitDate = Date(timeIntervalSince1970: 2_000_000_000)
            settings.settings.calibrationEnabledAt = Date()

            #expect(model.sensitivity == 0.9)
            #expect(model.notificationsEnabled)
        }
    }

    @Test func syncedSettingsFieldsRefreshIndependently() async {
        await withSettings { settings in
            let model = SettingsViewModel()
            model.bind(settings: settings)
            model.notificationsEnabled = true

            settings.settings.sensitivity = 0.8

            #expect(model.sensitivity == 0.8)
            #expect(model.notificationsEnabled)

            model.sensitivity = 0.2
            settings.settings.notificationsEnabled = true

            #expect(model.sensitivity == 0.2)
            #expect(model.notificationsEnabled)
        }
    }

    @Test func savingSettingsPreservesLatestGoalAndConsent() async {
        await withSettings { settings in
            let model = SettingsViewModel()
            model.bind(settings: settings)
            model.sensitivity = 0.9
            model.notificationsEnabled = false
            let target = Date(timeIntervalSince1970: 2_000_000_000)
            let consent = Date()
            settings.settings.dailyLimit = 4
            settings.settings.quitDate = target
            settings.settings.calibrationEnabledAt = consent

            await model.save(settings: settings)

            #expect(settings.settings.sensitivity == 0.9)
            #expect(settings.settings.notificationsEnabled == false)
            #expect(settings.settings.dailyLimit == 4)
            #expect(settings.settings.quitDate == target)
            #expect(settings.settings.calibrationEnabledAt == consent)
        }
    }

    private func withSettings(_ body: (UserSettingsStore) async -> Void) async {
        let suite = "CiggyFormDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        await body(UserSettingsStore(defaults: defaults))
    }
}
