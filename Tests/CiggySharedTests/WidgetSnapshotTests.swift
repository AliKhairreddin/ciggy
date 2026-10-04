import Foundation
import XCTest
@testable import CiggyShared

final class WidgetSnapshotTests: XCTestCase {
	private var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "America/Toronto")!
		return calendar
	}
	private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 3, _ hour: Int = 12, _ minute: Int = 0) -> Date {
		calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
	}

	func testTodayExcludesYesterdayAndFutureAndDeduplicatesDelivery() {
		let now = date()
		let event = SmokingEvent(timestamp: date(2026, 10, 3, 8), source: .manual)
		let events = [event, event,
			SmokingEvent(timestamp: date(2026, 10, 2, 23), source: .automatic),
			SmokingEvent(timestamp: date(2026, 10, 3, 15), source: .manual)]
		let state = LiveActivitySnapshot(events: events, dailyLimit: 10, now: now, calendar: calendar)
		XCTAssertEqual(state.dailyCount, 1)
		XCTAssertEqual(state.lastLoggedAt, event.timestamp)
		XCTAssertEqual(state.remaining, 9)
	}

	func testGoalChangesAndCountCorrectionsChangeSnapshot() {
		let now = date()
		let events = (0..<3).map { SmokingEvent(timestamp: now.addingTimeInterval(Double(-$0 * 60)), source: .manual) }
		let initial = WidgetSnapshot(events: events, dailyLimit: 10, now: now)
		let corrected = WidgetSnapshot(events: Array(events.dropFirst()), dailyLimit: 1, now: now)
		XCTAssertEqual(initial.today(at: now, calendar: calendar).dailyCount, 3)
		XCTAssertEqual(corrected.today(at: now, calendar: calendar).dailyCount, 2)
		XCTAssertEqual(corrected.today(at: now, calendar: calendar).remaining, 0)
		XCTAssertEqual(corrected.today(at: now, calendar: calendar).progress, 1)
		XCTAssertEqual(corrected.today(at: now, calendar: calendar).lastLoggedAt, events[1].timestamp)
	}

	func testMidnightTimelineResetsTodayButRetainsLastLog() {
		let last = date(2026, 10, 3, 23, 59)
		let snapshot = WidgetSnapshot(events: [SmokingEvent(timestamp: last, source: .manual)], dailyLimit: 10, now: last)
		let nextDay = snapshot.today(at: date(2026, 10, 4, 0), calendar: calendar)
		XCTAssertEqual(nextDay.dailyCount, 0)
		XCTAssertEqual(nextDay.remaining, 10)
		XCTAssertEqual(nextDay.lastLoggedAt, last)
		XCTAssertEqual(snapshot.week(at: date(2026, 10, 4, 0), calendar: calendar).map(\.count), [0, 0, 0, 0, 0, 1, 0])
	}

	func testFreshInstallHasNoInventedTimer() {
		let state = WidgetSnapshot(events: [], dailyLimit: 0, now: date()).today(at: date(), calendar: calendar)
		XCTAssertEqual(state.dailyCount, 0)
		XCTAssertEqual(state.dailyLimit, 1)
		XCTAssertNil(state.lastLoggedAt)
	}

	func testOldLastLogIsRetainedWithoutInflatingWeek() {
		let last = date(2026, 8, 1)
		let snapshot = WidgetSnapshot(events: [SmokingEvent(timestamp: last, source: .manual)], dailyLimit: 10, now: date())
		XCTAssertEqual(snapshot.today(at: date(), calendar: calendar).lastLoggedAt, last)
		XCTAssertEqual(snapshot.week(at: date(), calendar: calendar).reduce(0) { $0 + $1.count }, 0)
	}

	func testLiveActivityExpiresAtMidnightOrEightHours() {
		XCTAssertEqual(LiveActivitySnapshot.expiration(startingAt: date(), calendar: calendar), date(2026, 10, 3, 20))
		XCTAssertEqual(LiveActivitySnapshot.expiration(startingAt: date(2026, 10, 3, 23), calendar: calendar), date(2026, 10, 4, 0))
	}

	func testMidnightExpirationUsesCalendarAcrossDaylightSaving() {
		let start = date(2026, 11, 1, 20)
		XCTAssertEqual(LiveActivitySnapshot.expiration(startingAt: start, calendar: calendar), date(2026, 11, 2, 0))
	}

	func testSharedStorePersistsCorrectionsAndAvoidsDuplicateReloads() throws {
		let suite = "CiggyWidgetSnapshotTests.\(UUID())"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		let store = WidgetSnapshotStore(defaults: defaults)
		XCTAssertNil(store.read())
		let event = SmokingEvent(timestamp: date(), source: .manual, heartRate: 80, notes: "Private note")
		let original = WidgetSnapshot(events: [event], dailyLimit: 10, now: date())
		XCTAssertTrue(store.write(original))
		XCTAssertFalse(store.write(original))
		XCTAssertEqual(WidgetSnapshotStore(defaults: defaults).read(), original)
		let data = try XCTUnwrap(defaults.data(forKey: "Ciggy.widgets.snapshot.v1"))
		let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
		XCTAssertFalse(encoded.contains("Private note"))
		XCTAssertFalse(encoded.contains("heartRate"))
		let corrected = WidgetSnapshot(events: [], dailyLimit: 5, now: date())
		XCTAssertTrue(store.write(corrected))
		XCTAssertEqual(store.read(), corrected)
	}

	func testCorruptSharedStoreShowsUnconfiguredState() throws {
		let suite = "CiggyWidgetSnapshotTests.\(UUID())"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
		defer { defaults.removePersistentDomain(forName: suite) }
		defaults.set(Data("invalid".utf8), forKey: "Ciggy.widgets.snapshot.v1")
		XCTAssertNil(WidgetSnapshotStore(defaults: defaults).read())
	}
}
