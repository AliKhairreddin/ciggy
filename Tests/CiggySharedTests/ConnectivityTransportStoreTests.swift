import XCTest
@testable import CiggyShared

@MainActor
final class ConnectivityTransportStoreTests: XCTestCase {
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
