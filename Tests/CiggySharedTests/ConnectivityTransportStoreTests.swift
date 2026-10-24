import XCTest
@testable import CiggyShared

@MainActor
final class ConnectivityTransportStoreTests: XCTestCase {
    func testReusedTransportIDWithDifferentContentsIsNotAcknowledged() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConnectivityTransportStore(defaults: defaults)
        let original = ConnectivityEnvelope(type: "event", data: Data("original".utf8))
        let collision = ConnectivityEnvelope(id: original.id, type: "eventDeletion", data: Data("different".utf8))
        XCTAssertTrue(store.enqueue(original))
        XCTAssertTrue(store.receive(original))
        XCTAssertFalse(store.enqueue(collision))
        XCTAssertFalse(store.receive(collision))
        XCTAssertNotNil(store.lastPersistenceError)
        let restored = ConnectivityTransportStore(defaults: defaults)
        XCTAssertEqual(restored.outgoing, [original])
        XCTAssertEqual(restored.incoming, [original])
        XCTAssertTrue(store.receive(original))
        XCTAssertNil(store.lastPersistenceError)
    }

    func testAtomicInboxAndOutboxSurviveWithoutPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("transport.json")
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let envelope = ConnectivityEnvelope(type: "reviewCorrection.v2", data: Data("correction".utf8))
        let store = ConnectivityTransportStore(defaults: defaults, snapshotURL: file)
        XCTAssertTrue(store.enqueue(envelope))
        XCTAssertTrue(store.receive(envelope))
        defaults.removePersistentDomain(forName: name)
        let reloaded = ConnectivityTransportStore(defaults: defaults, snapshotURL: file)
        XCTAssertEqual(reloaded.outgoing, [envelope])
        XCTAssertEqual(reloaded.incoming, [envelope])
        XCTAssertTrue(reloaded.acknowledge(id: envelope.id))
        XCTAssertTrue(reloaded.didDeliver(id: envelope.id))
        let final = ConnectivityTransportStore(defaults: defaults, snapshotURL: file)
        XCTAssertTrue(final.outgoing.isEmpty)
        XCTAssertTrue(final.incoming.isEmpty)
    }

    func testFailedInboxSaveCannotAcknowledgeAndRetriesAfterDiskRecovers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("file blocking directory".utf8).write(to: directory)
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        // Construct before making its parent unavailable, so this tests write failure.
        let file = directory.appendingPathComponent("state.json")
        try FileManager.default.removeItem(at: directory)
        let store = ConnectivityTransportStore(defaults: defaults, snapshotURL: file)
        try Data("file blocking directory".utf8).write(to: directory)
        let event = ConnectivityEnvelope(type: "event", data: Data("event".utf8))
        XCTAssertFalse(store.receive(event))
        XCTAssertFalse(store.enqueue(event))
        XCTAssertTrue(store.incoming.isEmpty)
        XCTAssertTrue(store.outgoing.isEmpty)
        XCTAssertNotNil(store.lastPersistenceError)
        try FileManager.default.removeItem(at: directory)
        XCTAssertTrue(store.receive(event))
        XCTAssertTrue(store.enqueue(event))
        XCTAssertNil(store.lastPersistenceError)
        XCTAssertEqual(ConnectivityTransportStore(defaults: defaults, snapshotURL: file).incoming, [event])
    }

    func testUnreadableJournalIsNeverOverwrittenWithEmptyState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let corrupt = Data("saved but malformed".utf8)
        try corrupt.write(to: file)
        let store = ConnectivityTransportStore(snapshotURL: file)
        XCTAssertFalse(store.enqueue(.init(type: "event", data: Data())))
        XCTAssertNotNil(store.lastPersistenceError)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testOnlyMutationMessagesRequireAnApplicationPersistenceReceipt() {
        for type in ["event", "eventDeletion", "detectionReview", "reviewCorrection.v2"] {
            XCTAssertTrue(ConnectivityEnvelope(type: type, data: Data()).requiresDurableReceipt)
        }
        for type in ["transportReceipt.v2", "trackingStatus", "historyRefreshRequest", "settings"] {
            XCTAssertFalse(ConnectivityEnvelope(type: type, data: Data()).requiresDurableReceipt)
        }
    }

    func testRepeatedChecksAndStatusCoalesceWithoutDroppingEventMutations() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConnectivityTransportStore(defaults: defaults)
        let event = ConnectivityEnvelope(type: "event", data: Data("cigarette".utf8))
        store.enqueue(event)
        for number in 0..<100 {
            store.enqueueLatest(.init(type: "historyRefreshRequest", data: Data("request \(number)".utf8)))
            store.enqueueLatest(.init(type: "trackingStatus", data: Data("status \(number)".utf8)))
        }
        let reloaded = ConnectivityTransportStore(defaults: defaults)
        XCTAssertEqual(reloaded.outgoing.count, 3)
        XCTAssertEqual(reloaded.outgoing.first, event)
        XCTAssertEqual(reloaded.outgoing.last?.data, Data("status 99".utf8))
        store.enqueueLatest(.init(type: "eventDeletion", data: Data("a".utf8)))
        store.enqueueLatest(.init(type: "eventDeletion", data: Data("b".utf8)))
        XCTAssertEqual(store.outgoing.filter { $0.type == "eventDeletion" }.count, 2)
    }

    func testRepeatedSendOfSameMutationCoalescesUntilAcknowledged() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConnectivityTransportStore(defaults: defaults)
        let original = ConnectivityEnvelope(type: "event", data: Data("same event".utf8))
        store.enqueue(original)
        store.enqueue(.init(type: "event", data: original.data))
        store.enqueue(.init(type: "eventDeletion", data: original.data))
        XCTAssertEqual(store.outgoing.count, 2)
        XCTAssertEqual(store.outgoing.first?.id, original.id)
        store.acknowledge(id: original.id)
        XCTAssertEqual(store.outgoing.map(\.type), ["eventDeletion"])
    }

    func testLatestSettingsPersistBeforeActivationAndRemoteUpdateClearsReplay() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ConnectivityTransportStore(defaults: defaults)
        store.replaceSettings(.init(type: "settings", data: Data("old".utf8)))
        let latest = ConnectivityEnvelope(type: "settings", data: Data("new".utf8))
        store.replaceSettings(latest)
        let relaunched = ConnectivityTransportStore(defaults: defaults)
        XCTAssertEqual(relaunched.latestSettings, latest)
        relaunched.clearSettings()
        XCTAssertNil(ConnectivityTransportStore(defaults: defaults).latestSettings)
    }

    func testLegacyTransportStateLoadsWithoutSettingsField() throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let envelope = ConnectivityEnvelope(type: "event", data: Data("saved".utf8))
        defaults.set(try JSONEncoder().encode(["outgoing": [envelope], "incoming": []]), forKey: "transport")
        let store = ConnectivityTransportStore(defaults: defaults, key: "transport")
        XCTAssertEqual(store.outgoing, [envelope])
        XCTAssertNil(store.latestSettings)
    }

    func testUnacknowledgedMutationSurvivesRelaunchAndDuplicateQueueing() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let envelope = ConnectivityEnvelope(type: "event", data: Data("smoke".utf8))
        let store = ConnectivityTransportStore(defaults: defaults)
        store.enqueue(envelope); store.enqueue(envelope)
        let relaunched = ConnectivityTransportStore(defaults: defaults)
        XCTAssertEqual(relaunched.outgoing, [envelope])
        relaunched.acknowledge(id: UUID())
        XCTAssertEqual(relaunched.outgoing, [envelope])
        relaunched.acknowledge(id: envelope.id)
        XCTAssertTrue(ConnectivityTransportStore(defaults: defaults).outgoing.isEmpty)
    }

    func testColdLaunchInboxPersistsUntilRepositoriesCanReceiveIt() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let envelope = ConnectivityEnvelope(type: "eventDeletion", data: Data())
        let store = ConnectivityTransportStore(defaults: defaults)
        store.receive(envelope); store.receive(envelope)
        let relaunched = ConnectivityTransportStore(defaults: defaults)
        XCTAssertEqual(relaunched.incoming, [envelope])
        relaunched.didDeliver(id: envelope.id)
        XCTAssertTrue(ConnectivityTransportStore(defaults: defaults).incoming.isEmpty)
    }

    func testCorrectedAutomaticSessionCannotBeRestoredByHistory() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let date = Date()
        let repo = EventRepository(userDefaults: defaults)
        let event = SmokingEvent(timestamp: date, source: .automatic)
        repo.addEvent(event); repo.removeEvent(id: event.id)
        let relaunched = EventRepository(userDefaults: defaults)
        XCTAssertTrue(relaunched.events.isEmpty)
        XCTAssertTrue(relaunched.hasRecordedAutomaticSession(near: date.addingTimeInterval(15)))
        XCTAssertFalse(relaunched.hasRecordedAutomaticSession(near: date.addingTimeInterval(600)))
    }
}
