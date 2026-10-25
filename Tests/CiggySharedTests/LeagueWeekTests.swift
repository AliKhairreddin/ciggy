import XCTest
@testable import CiggyShared

final class LeagueWeekTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testUTCWeekChangesAtMondayAndPreviousWeekCrossesYearBoundary() {
        let sunday = LeagueWeek(containing: date("2027-01-03T23:59:59Z"))
        let monday = LeagueWeek(containing: date("2027-01-04T00:00:00Z"))
        XCTAssertEqual(sunday.key, "2026-12-28")
        XCTAssertEqual(monday.key, "2027-01-04")
        XCTAssertEqual(sunday.end, monday.start)
        XCTAssertEqual(LeagueWeek(containing: monday.start, previous: true), sunday)
        XCTAssertEqual(monday.end.timeIntervalSince(monday.start), 7 * 86400)
    }

    func testWeeklyCountsDeduplicateIDsAndExcludeFutureAndOutsideWindow() {
        let now = date("2026-10-24T12:00:00Z")
        let current = LeagueWeek(containing: now)
        let previous = LeagueWeek(containing: now, previous: true)
        let duplicateID = UUID()
        let events = [
            SmokingEvent(timestamp: previous.start.addingTimeInterval(-1), source: .manual),
            SmokingEvent(timestamp: previous.start, source: .manual),
            SmokingEvent(timestamp: current.start.addingTimeInterval(-1), source: .manual),
            SmokingEvent(id: duplicateID, timestamp: current.start, source: .automatic),
            SmokingEvent(id: duplicateID, timestamp: current.start, source: .automatic),
            SmokingEvent(timestamp: now, source: .manual),
            SmokingEvent(timestamp: now.addingTimeInterval(1), source: .manual),
            SmokingEvent(timestamp: current.end, source: .manual)
        ]
        XCTAssertEqual(current.count(events: events, through: now), 2)
        XCTAssertEqual(previous.count(events: events, through: now), 2)
        XCTAssertEqual(LeagueWeek(containing: current.end).count(events: events, through: current.end), 1)
    }

    func testUTCSeasonsDoNotUseOffsetDatesOrDaylightSavingLength() {
        // Still Sunday UTC, despite this ISO timestamp's Monday calendar date.
        let localMonday = date("2026-03-09T00:30:00+14:00")
        let week = LeagueWeek(containing: localMonday)
        XCTAssertEqual(week.key, "2026-03-02")
        XCTAssertEqual(week.end, date("2026-03-09T00:00:00Z"))
        XCTAssertEqual(week.end.timeIntervalSince(week.start), 604800)
    }
}
