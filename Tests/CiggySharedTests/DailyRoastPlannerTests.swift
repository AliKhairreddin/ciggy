import XCTest
@testable import CiggyShared

@MainActor
final class DailyRoastPlannerTests: XCTestCase {
	private var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		return calendar
	}
	private var today: Date {
		calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
	}

	func testCatalogContains110DistinctMessagesWithoutUnfilledPlaceholders() {
		let messages = DailyRoastCopy.previews
		XCTAssertEqual(messages.count, 110)
		XCTAssertEqual(Set(messages.map(\.title)).count, 110)
		XCTAssertEqual(Set(messages.map(\.body)).count, 110)
		for message in messages {
			XCTAssertFalse(message.body.contains("{"))
			XCTAssertFalse(message.title.isEmpty)
			XCTAssertLessThan(message.body.count, 180)
		}
		XCTAssertTrue(DailyRoastCopy.variants(for: 3).allSatisfy { $0.body.contains("3 cigarettes today") })
		XCTAssertTrue(DailyRoastCopy.variants(for: 1).allSatisfy { $0.body.contains("1 cigarette today") })
	}

	func testOnlyNewMilestonesNotifyAndCorrectionsDoNotRepeatThem() {
		withPlanner { planner, _ in
			XCTAssertNil(planner.next(count: 0, enabled: true, at: today, calendar: calendar))
			XCTAssertNotNil(planner.next(count: 1, enabled: true, at: today, calendar: calendar))
			XCTAssertNil(planner.next(count: 2, enabled: true, at: today, calendar: calendar))
			XCTAssertNotNil(planner.next(count: 5, enabled: true, at: today, calendar: calendar))
			XCTAssertNil(planner.next(count: 5, enabled: true, at: today, calendar: calendar))
			XCTAssertNil(planner.next(count: 4, enabled: true, at: today, calendar: calendar))
			XCTAssertNil(planner.next(count: 5, enabled: true, at: today, calendar: calendar))
		}
	}

	func testHistoryBatchUsesActualCountAndOnlyHighestCrossedMilestone() {
		withPlanner { planner, _ in
			_ = planner.next(count: 4, dailyLimit: 100, enabled: false, at: today, calendar: calendar)
			let message = planner.next(count: 16, dailyLimit: 100, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(message?.body.contains("16 cigarettes today") == true)
			XCTAssertNil(planner.next(count: 16, dailyLimit: 100, enabled: true, at: today, calendar: calendar))
		}
	}

	func testCustomLimitAndExceedingItHaveSeparateScenarios() {
		withPlanner { planner, _ in
			_ = planner.next(count: 6, dailyLimit: 7, enabled: false, at: today, calendar: calendar)
			let reached = planner.next(count: 7, dailyLimit: 7, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .limitReached, count: 7, limit: 7).contains { $0 == reached })
			let exceeded = planner.next(count: 8, dailyLimit: 7, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .limitExceeded, count: 8, limit: 7).contains { $0 == exceeded })
			XCTAssertNil(planner.next(count: 9, dailyLimit: 7, enabled: true, at: today, calendar: calendar))
		}
	}

	func testDefaultTenMilestoneKeepsDoubleDigitRoast() {
		withPlanner { planner, _ in
			_ = planner.next(count: 9, enabled: false, at: today, calendar: calendar)
			let message = planner.next(count: 10, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .ten, count: 10).contains { $0 == message })
			XCTAssertNotNil(planner.next(count: 11, enabled: true, at: today, calendar: calendar))
		}
	}

	func testDisabledAndStartupBaselineDoNotQueueOldMilestones() {
		withPlanner { planner, _ in
			XCTAssertNil(planner.next(count: 10, enabled: false, at: today, calendar: calendar))
			XCTAssertNil(planner.next(count: 10, enabled: true, at: today, calendar: calendar))
			XCTAssertNotNil(planner.next(count: 11, enabled: true, at: today, calendar: calendar))
		}
	}

	func testPersistedRotationVisitsAllTenLinesBeforeRepeating() {
		withPlanner { planner, defaults in
			var activePlanner = planner
			var messages: [DailyRoast] = []
			for offset in 0...10 {
				let date = calendar.date(byAdding: .day, value: offset, to: today)!
				if let message = activePlanner.next(count: 10, enabled: true, at: date, calendar: calendar) {
					messages.append(message)
				}
				activePlanner = DailyRoastPlanner(userDefaults: defaults, storageKey: "roasts")
				XCTAssertNil(activePlanner.next(count: 10, enabled: true, at: date, calendar: calendar))
			}
			XCTAssertEqual(messages.count, 11)
			XCTAssertEqual(Set(messages.prefix(10).map(\.body)).count, 10)
			XCTAssertEqual(messages.first, messages.last)
		}
	}

	func testLocalMidnightResetsEvenAcrossDaylightSavingTime() {
		withPlanner { planner, _ in
			let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 59))!
			let nextMorning = calendar.date(byAdding: .minute, value: 2, to: late)!
			XCTAssertNotNil(planner.next(count: 1, enabled: true, at: late, calendar: calendar))
			XCTAssertNotNil(planner.next(count: 1, enabled: true, at: nextMorning, calendar: calendar))
		}
	}

	func testFreshInstallAndPartialFirstDayNeverClaimSmokeFreeAchievement() {
		withPlanner { planner, _ in
			XCTAssertNil(planner.recap(events: [], dailyLimit: 10, enabled: true, at: today, calendar: calendar))
			XCTAssertNil(planner.recap(events: events(count: 1, daysAgo: 1), dailyLimit: 10, enabled: true, at: today, calendar: calendar))
		}
	}

	func testSmokeFreeRecapIsBasedOnCompletedDayAndPersistsDeduplication() {
		withPlanner { planner, defaults in
			let history = events(count: 4, daysAgo: 2) + events(count: 1, daysAgo: 0)
			let message = planner.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .smokeFree, count: 0).contains { $0 == message })
			let reloaded = DailyRoastPlanner(userDefaults: defaults, storageKey: "roasts")
			XCTAssertNil(reloaded.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar))
		}
	}

	func testReductionRecapTakesPriorityOverBeingBelowLimit() {
		withPlanner { planner, _ in
			let history = events(count: 8, daysAgo: 2) + events(count: 4, daysAgo: 1)
			let message = planner.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .reduced, count: 4, previousCount: 8).contains { $0 == message })
		}
	}

	func testBelowLimitRecapAndDisabledRecap() {
		withPlanner { planner, defaults in
			let history = events(count: 2, daysAgo: 2) + events(count: 4, daysAgo: 1)
			let message = planner.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar)
			XCTAssertTrue(DailyRoastCopy.variants(for: .belowLimit, count: 4).contains { $0 == message })
			let disabled = DailyRoastPlanner(userDefaults: defaults, storageKey: "disabled")
			XCTAssertNil(disabled.recap(events: history, dailyLimit: 10, enabled: false, at: today, calendar: calendar))
			XCTAssertNil(disabled.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar))
		}
	}

	func testOverLimitDayDoesNotReceiveAFalsePositiveAchievement() {
		withPlanner { planner, _ in
			let history = events(count: 8, daysAgo: 2) + events(count: 12, daysAgo: 1)
			XCTAssertNil(planner.recap(events: history, dailyLimit: 10, enabled: true, at: today, calendar: calendar))
		}
	}

	private func events(count: Int, daysAgo: Int) -> [SmokingEvent] {
		let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
		return (0..<count).map { SmokingEvent(timestamp: date.addingTimeInterval(Double($0)), source: .manual) }
	}

	private func withPlanner(_ body: (DailyRoastPlanner, UserDefaults) -> Void) {
		let suite = "DailyRoastPlannerTests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		defer { defaults.removePersistentDomain(forName: suite) }
		body(DailyRoastPlanner(userDefaults: defaults, storageKey: "roasts"), defaults)
	}
}
