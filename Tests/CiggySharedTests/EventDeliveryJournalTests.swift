import Foundation
import XCTest
@testable import CiggyShared

@MainActor
final class EventDeliveryJournalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000.123456)

    func testFailedSourceWriteDoesNotPublishEventOrItsIntent() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url,
                snapshotWriter: { _ in throw CocoaError(.fileWriteOutOfSpace) })
            var sent = 0
            repository.configureEventDelivery(enqueueEvent: { _ in sent += 1; return true },
                enqueueDeletion: { _ in sent += 1; return true })
            XCTAssertFalse(repository.addEvent(event()))
            XCTAssertTrue(repository.events.isEmpty)
            XCTAssertEqual(repository.pendingEventMutationCount, 0)
            XCTAssertEqual(sent, 0)
            XCTAssertNotNil(repository.lastPersistenceError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testRestartAfterLocalSaveBeforeQueueRecoversExactEventPayload() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url)
            let original = event()
            XCTAssertTrue(repository.addEvent(original))
            XCTAssertEqual(repository.pendingEventMutationCount, 1)
            let restored = EventRepository(userDefaults: defaults, snapshotURL: url)
            var sent: [SmokingEvent] = []
            restored.configureEventDelivery(enqueueEvent: { sent.append($0); return true }, enqueueDeletion: { _ in true })
            XCTAssertEqual(sent, [original])
            XCTAssertEqual(restored.events, [original])
            XCTAssertEqual(restored.pendingEventMutationCount, 0)
            let again = EventRepository(userDefaults: defaults, snapshotURL: url)
            again.configureEventDelivery(enqueueEvent: { sent.append($0); return true }, enqueueDeletion: { _ in true })
            XCTAssertEqual(sent.count, 1)
            XCTAssertEqual(again.pendingEventMutationCount, 0)
        }
    }

    func testAlreadyQueuedEventIntentSurvivesFailedClearAndReplaysIdempotently() throws {
        try withFiles { defaults, url in
            var failWrite = false
            let file = DurableSnapshotFile(url: url)
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url, snapshotWriter: { data in
                if failWrite { throw CocoaError(.fileWriteOutOfSpace) }
                try file.write(data)
            })
            let original = event()
            XCTAssertTrue(repository.addEvent(original))
            var sent: [SmokingEvent] = []
            repository.configureEventDelivery(enqueueEvent: {
                sent.append($0)
                failWrite = true // Transport saved it; retiring the source intent fails.
                return true
            }, enqueueDeletion: { _ in true })
            XCTAssertEqual(repository.pendingEventMutationCount, 1)
            XCTAssertNotNil(repository.lastPersistenceError)
            let restored = EventRepository(userDefaults: defaults, snapshotURL: url)
            restored.configureEventDelivery(enqueueEvent: { sent.append($0); return true }, enqueueDeletion: { _ in true })
            XCTAssertEqual(sent, [original, original])
            XCTAssertEqual(restored.pendingEventMutationCount, 0)
            try withFiles { remoteDefaults, remoteURL in
                let remote = EventRepository(userDefaults: remoteDefaults, snapshotURL: remoteURL)
                for item in sent { XCTAssertTrue(remote.receiveEvent(item)) }
                XCTAssertEqual(remote.events, [original])
                XCTAssertEqual(remote.pendingEventMutationCount, 0)
            }
        }
    }

    func testAddThenDeleteBeforeFlushPreservesBothIntentsAndAnyDeliveryOrder() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url)
            let original = event()
            XCTAssertTrue(repository.addEvent(original))
            XCTAssertTrue(repository.removeEvent(id: original.id))
            XCTAssertTrue(repository.events.isEmpty)
            XCTAssertEqual(repository.pendingEventMutationCount, 2)
            let restored = EventRepository(userDefaults: defaults, snapshotURL: url)
            var sent: [SmokingEvent] = []
            var deleted: [UUID] = []
            var order: [String] = []
            restored.configureEventDelivery(enqueueEvent: { sent.append($0); order.append("add"); return true },
                enqueueDeletion: { deleted.append($0); order.append("delete"); return true })
            XCTAssertEqual(sent, [original], "The intent keeps the payload after the base event was deleted.")
            XCTAssertEqual(deleted, [original.id])
            XCTAssertEqual(order, ["add", "delete"])
            XCTAssertEqual(restored.pendingEventMutationCount, 0)
            for deleteFirst in [true, false] {
                try withFiles { remoteDefaults, remoteURL in
                    let remote = EventRepository(userDefaults: remoteDefaults, snapshotURL: remoteURL)
                    if deleteFirst { XCTAssertTrue(remote.receiveDeletion(id: original.id)) }
                    XCTAssertTrue(remote.receiveEvent(original))
                    XCTAssertTrue(remote.receiveDeletion(id: original.id))
                    XCTAssertTrue(remote.receiveEvent(original))
                    XCTAssertTrue(remote.events.isEmpty)
                    XCTAssertEqual(remote.pendingEventMutationCount, 0)
                }
            }
        }
    }

    func testIncomingMutationsNeverCreateOutboundEchoAndFlushCannotReenter() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url)
            var sends = 0
            repository.configureEventDelivery(enqueueEvent: { _ in
                sends += 1
                XCTAssertFalse(repository.retryPendingEventMutations())
                return true
            }, enqueueDeletion: { _ in sends += 1; return true })
            let received = event()
            XCTAssertTrue(repository.receiveEvent(received))
            XCTAssertTrue(repository.receiveDeletion(id: received.id))
            XCTAssertEqual(sends, 0)
            XCTAssertEqual(repository.pendingEventMutationCount, 0)
            XCTAssertTrue(repository.addEvent(event()))
            XCTAssertEqual(sends, 1)
            XCTAssertEqual(repository.pendingEventMutationCount, 0)
            let detected = SmokingEvent(timestamp: now.addingTimeInterval(300), source: .automatic)
            let correction = DetectionReview(eventIDs: [detected.id], origin: .watchHistory,
                windowStart: detected.timestamp, windowEnd: detected.timestamp, decision: .adjusted,
                correctedCount: 2, updatedAt: now, eventSnapshots: [detected], correction: .init(decidedAt: now))
            XCTAssertTrue(repository.applyCorrections([correction]))
            XCTAssertEqual(repository.events.count, 3)
            XCTAssertEqual(sends, 1, "Whole-review corrections must not emit legacy event mutations.")
            XCTAssertEqual(repository.pendingEventMutationCount, 0)
        }
    }

    func testFailedEnqueueAndFailedDeletionWriteRemainRetryable() throws {
        try withFiles { defaults, url in
            var queueWorks = false
            var writeWorks = true
            let file = DurableSnapshotFile(url: url)
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url, snapshotWriter: { data in
                if !writeWorks { throw CocoaError(.fileWriteOutOfSpace) }
                try file.write(data)
            })
            var sent: [SmokingEvent] = []
            var deletions: [UUID] = []
            repository.configureEventDelivery(enqueueEvent: {
                if queueWorks { sent.append($0) }
                return queueWorks
            }, enqueueDeletion: { deletions.append($0); return true })
            let original = event()
            XCTAssertTrue(repository.addEvent(original), "The local event and intent are durable even while enqueue fails.")
            XCTAssertEqual(repository.pendingEventMutationCount, 1)
            XCTAssertNotNil(repository.lastPersistenceError)
            writeWorks = false
            XCTAssertFalse(repository.removeEvent(id: original.id))
            XCTAssertEqual(repository.events, [original])
            XCTAssertEqual(repository.pendingEventMutationCount, 1)
            writeWorks = true
            queueWorks = true
            XCTAssertTrue(repository.retryPendingEventMutations())
            XCTAssertEqual(sent, [original])
            XCTAssertTrue(repository.removeEvent(id: original.id))
            XCTAssertEqual(deletions, [original.id])
            XCTAssertFalse(repository.removeEvent(id: original.id), "Changed-Bool semantics remain idempotent.")
            XCTAssertNil(repository.lastPersistenceError)
            XCTAssertEqual(deletions, [original.id])
        }
    }

    func testRemoveAllJournalsOnlyExplicitDeletions() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url)
            let first = event()
            let second = event()
            XCTAssertTrue(repository.receiveEvent(first))
            XCTAssertTrue(repository.receiveEvent(second))
            repository.removeAll()
            XCTAssertTrue(repository.events.isEmpty)
            XCTAssertEqual(repository.pendingEventMutationCount, 2)
            var deletions: [UUID] = []
            let restored = EventRepository(userDefaults: defaults, snapshotURL: url)
            restored.configureEventDelivery(enqueueEvent: { _ in XCTFail("No received event should be echoed"); return false },
                enqueueDeletion: { deletions.append($0); return true })
            XCTAssertEqual(Set(deletions), Set([first.id, second.id]))
            XCTAssertEqual(restored.pendingEventMutationCount, 0)
        }
    }

    func testCorruptPendingIntentBlocksWritesAndPreservesTheSavedBytes() throws {
        try withFiles { defaults, url in
            let repository = EventRepository(userDefaults: defaults, snapshotURL: url)
            XCTAssertTrue(repository.addEvent(event()))
            var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            var pending = try XCTUnwrap(encoded["pendingEventMutations"] as? [[String: Any]])
            pending[0].removeValue(forKey: "event")
            encoded["pendingEventMutations"] = pending
            let corrupt = try JSONSerialization.data(withJSONObject: encoded, options: .sortedKeys)
            try corrupt.write(to: url)
            let restored = EventRepository(userDefaults: defaults, snapshotURL: url)
            var sent = 0
            restored.configureEventDelivery(enqueueEvent: { _ in sent += 1; return true },
                enqueueDeletion: { _ in sent += 1; return true })
            XCTAssertFalse(restored.receiveEvent(event()))
            XCTAssertFalse(restored.receiveDeletion(id: UUID()))
            XCTAssertFalse(restored.addEvent(event()))
            XCTAssertFalse(restored.retryPendingEventMutations())
            XCTAssertNotNil(restored.lastPersistenceError)
            XCTAssertEqual(sent, 0)
            XCTAssertEqual(try Data(contentsOf: url), corrupt)
        }
    }

    private func event() -> SmokingEvent {
        SmokingEvent(timestamp: now, source: .manual, notes: "Manual log draft")
    }

    private func withFiles(_ body: (UserDefaults, URL) throws -> Void) throws {
        let suite = "EventDeliveryJournalTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(defaults, directory.appendingPathComponent("events.json"))
    }
}
