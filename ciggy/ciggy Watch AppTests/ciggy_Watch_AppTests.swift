//
//  ciggy_Watch_AppTests.swift
//  ciggy Watch AppTests
//
//  Created by Ali Khairreddin on 2026-07-14.
//

import Combine
import Foundation
import CiggyShared
import Testing
@testable import ciggy_Watch_App

@MainActor
struct ciggy_Watch_AppTests {
    @Test func freshManualLogUpdatesBeforeTheNextTimerTick() async throws {
        let suite = "CiggyWatchDashboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = EventRepository(userDefaults: defaults)
        let model = WatchDashboardViewModel()
        var updates = 0
        let subscription = model.$todayCount.sink { _ in updates += 1 }
        defer { subscription.cancel() }
        model.bind(repository: repository)

        // Wait for the initial timer/prepend emission, then log at a later time.
        // The old implementation incorrectly treated this fresh event as future.
        try await waitFor { updates >= 2 }
        let previousUpdates = updates
        repository.addEvent(SmokingEvent(timestamp: Date(), source: .manual))
        try await waitFor { updates > previousUpdates }

        #expect(model.todayCount == 1)
        #expect(model.timeSinceLast != "—")
    }

    @Test func futureCompanionLogDoesNotChangeCurrentCountOrLastLog() async throws {
        let suite = "CiggyWatchDashboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = EventRepository(userDefaults: defaults)
        let model = WatchDashboardViewModel()
        var updates = 0
        let subscription = model.$todayCount.sink { _ in updates += 1 }
        defer { subscription.cancel() }
        model.bind(repository: repository)
        try await waitFor { updates >= 2 }

        let previousUpdates = updates
        repository.addEvent(SmokingEvent(timestamp: Date().addingTimeInterval(3_600), source: .manual))
        try await waitFor { updates > previousUpdates }

        #expect(model.todayCount == 0)
        #expect(model.timeSinceLast == "—")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        // Fail within one second, well before the dashboard's 30-second timer.
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition(), "The dashboard did not process the event promptly")
    }
}
