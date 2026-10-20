import XCTest
@testable import CiggyShared

@MainActor
final class EventRepositoryTests: XCTestCase {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "EventRepositoryTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    func testInvalidDatesCannotPoisonPersistedHistory() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = EventRepository(userDefaults: defaults)
        let event = SmokingEvent(source: .manual)
        XCTAssertTrue(repository.addEvent(event))
        for timestamp in [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                          Date(timeIntervalSince1970: 1e20)] {
            XCTAssertFalse(repository.addEvent(.init(timestamp: timestamp, source: .automatic)))
            XCTAssertEqual(repository.dailyCount(on: timestamp), 0)
            XCTAssertEqual(repository.streakSmokeFreeDays(considering: timestamp), 0)
        }
        XCTAssertEqual(EventRepository(userDefaults: defaults).events, [event])
    }

    func testInvalidOptionalHeartRateDoesNotDiscardTheEvent() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = EventRepository(userDefaults: defaults)
        let event = SmokingEvent(source: .automatic, heartRate: .nan)
        XCTAssertTrue(repository.addEvent(event))
        let restored = EventRepository(userDefaults: defaults)
        XCTAssertEqual(restored.events.map(\.id), [event.id])
        XCTAssertNil(restored.events.first?.heartRate)
    }

    func testLegacyDuplicateHistoryMigratesWithDeletionAndAutomaticSessionMemory() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let automatic = SmokingEvent(source: .automatic)
        let manual = SmokingEvent(source: .manual)
        defaults.set(try JSONEncoder().encode([automatic, manual, manual]), forKey: "events")
        defaults.set(try JSONEncoder().encode([automatic.id]), forKey: "events.deleted.v1")
        defaults.set(try JSONEncoder().encode([automatic.id: automatic.timestamp]), forKey: "events.automaticTimes.v1")
        let repository = EventRepository(userDefaults: defaults, storageKey: "events")
        XCTAssertEqual(repository.events, [manual])
        XCTAssertTrue(repository.hasRecordedAutomaticSession(near: automatic.timestamp))
        repository.removeEvent(id: manual.id)
        // The new atomic snapshot must remain authoritative even if legacy keys disappear.
        defaults.removeObject(forKey: "events.deleted.v1")
        defaults.removeObject(forKey: "events.automaticTimes.v1")
        let restored = EventRepository(userDefaults: defaults, storageKey: "events")
        XCTAssertTrue(restored.events.isEmpty)
        XCTAssertFalse(restored.addEvent(manual))
        XCTAssertFalse(restored.addEvent(automatic))
        XCTAssertTrue(restored.hasRecordedAutomaticSession(near: automatic.timestamp))
    }

    func testDeletionArrivingBeforeEventRemainsIdempotentAfterRelaunch() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let event = SmokingEvent(source: .automatic)
        let repository = EventRepository(userDefaults: defaults)
        XCTAssertFalse(repository.removeEvent(id: event.id))
        let restored = EventRepository(userDefaults: defaults)
        XCTAssertFalse(restored.addEvent(event))
        XCTAssertFalse(restored.addEvent(event))
        XCTAssertTrue(restored.events.isEmpty)
    }

    func testStreakUsesCalendarDaysAcrossDaylightSavingAndIgnoresFutureEvents() throws {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = EventRepository(userDefaults: defaults)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastSmoke = try XCTUnwrap(calendar.date(byAdding: .day, value: -400, to: today))
        repository.addEvent(.init(timestamp: lastSmoke, source: .manual))
        repository.addEvent(.init(timestamp: today.addingTimeInterval(10 * 86_400), source: .manual))
        XCTAssertEqual(repository.streakSmokeFreeDays(considering: today), 400)
        repository.addEvent(.init(timestamp: today, source: .manual))
        XCTAssertEqual(repository.streakSmokeFreeDays(considering: today), 0)
    }

    func testSavingsAvoidIntegerOverflowAndRejectInvalidCost() {
        let (name, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = EventRepository(userDefaults: defaults)
        defaults.set(Int.max, forKey: "baselineCigsPerDay")
        repository.addEvent(.init(timestamp: Date().addingTimeInterval(-3 * 86_400), source: .manual))
        XCTAssertTrue(repository.estimatedMoneySaved().isFinite)
        XCTAssertGreaterThan(repository.estimatedMoneySaved(), 0)
        XCTAssertEqual(repository.estimatedMoneySaved(costPerCigarette: .nan), 0)
        XCTAssertEqual(repository.estimatedMoneySaved(costPerCigarette: .infinity), 0)
    }
}
