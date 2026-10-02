import XCTest
@testable import CiggyShared

@MainActor
final class ConnectivityTransportStoreTests: XCTestCase {
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
