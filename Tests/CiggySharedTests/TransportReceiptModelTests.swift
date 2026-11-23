import Foundation
import XCTest
import CiggyShared

@MainActor
final class TransportReceiptModelTests: XCTestCase {
    private enum Callback: CaseIterable {
        case systemTransfer, legacyReply, wrongReplyID, savedReply, persistedInbox, failedReceiptWrite, restart
    }

    func testOutboxAcrossCompletionsFailedWritesAndRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("transport.json")
        let suite = "TransportReceiptModel-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let durable = ["event", "eventDeletion", "detectionReview", "reviewCorrection.v2", "unknownType"]
        let ephemeral = ["transportReceipt.v2", "trackingStatus", "historyRefreshRequest", "settings"]
        for type in durable + ephemeral {
            let envelope = ConnectivityEnvelope(type: type, data: Data())
            for first in Callback.allCases {
                for second in Callback.allCases {
                    func reopen() -> ConnectivityTransportStore {
                        ConnectivityTransportStore(defaults: defaults, snapshotURL: url)
                    }
                    var store = reopen()
                    XCTAssertTrue(store.enqueue(envelope))
                    var expected = [envelope]
                    for callback in [first, second] {
                        switch callback {
                        case .systemTransfer:
                            store.confirm(id: envelope.id, via: .systemTransfer)
                            if ephemeral.contains(type) { expected = [] }
                        case .legacyReply:
                            store.confirm(id: envelope.id, via: .liveReply(acknowledgedID: envelope.id.uuidString, durableProtocol: nil))
                            if ephemeral.contains(type) { expected = [] }
                        case .wrongReplyID:
                            store.confirm(id: envelope.id, via: .liveReply(acknowledgedID: UUID().uuidString, durableProtocol: 2))
                        case .savedReply:
                            store.confirm(id: envelope.id, via: .liveReply(acknowledgedID: envelope.id.uuidString, durableProtocol: 2))
                            expected = []
                        case .persistedInbox:
                            store.confirm(id: envelope.id, via: .persistedInbox)
                            expected = []
                        case .failedReceiptWrite:
                            try withUnwritableSnapshot(at: url) {
                                _ = store.confirm(id: envelope.id, via: .persistedInbox)
                            }
                        case .restart:
                            store = reopen()
                        }
                        let trace = "\(type), \(first) then \(second), after \(callback)"
                        guard store.outgoing == expected, reopen().outgoing == expected else {
                            throw Violation(trace: trace, shouldBeQueued: !expected.isEmpty)
                        }
                    }
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func withUnwritableSnapshot(at url: URL, perform: () -> Void) throws {
        let files = FileManager.default
        let saved = url.appendingPathExtension("saved")
        try files.moveItem(at: url, to: saved)
        try files.createDirectory(at: url, withIntermediateDirectories: false)
        perform()
        try files.removeItem(at: url)
        try files.moveItem(at: saved, to: url)
    }

    private struct Violation: Error, CustomStringConvertible {
        let trace: String
        let shouldBeQueued: Bool
        var description: String { "\(trace): expected envelope to be \(shouldBeQueued ? "queued" : "retired")" }
    }
}
