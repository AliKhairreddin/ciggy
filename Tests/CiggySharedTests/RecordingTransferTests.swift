import Foundation
import XCTest
@testable import CiggyShared

final class RecordingTransferTests: XCTestCase {
    private enum Failure: Error { case disk }

    func testOutOfOrderDuplicateFramesSurviveRelaunchAndAcknowledgeOnlySavedBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let durable = root.appendingPathComponent("saved.json")
        let data = try recording(), frames = try RecordingTransfer.frames(for: data)
        XCTAssertGreaterThan(frames.count, 1)
        let persist: @Sendable (Data) throws -> Void = { data in
            guard !FileManager.default.fileExists(atPath: durable.path) else { throw Failure.disk }
            try data.write(to: durable, options: .atomic)
        }
        var inbox = RecordingTransferInbox(directory: root.appendingPathComponent("parts"), persist: persist)
        XCTAssertNil(try inbox.receive(frames.last!))
        XCTAssertNil(try inbox.receive(frames.last!))
        XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path))
        inbox = RecordingTransferInbox(directory: root.appendingPathComponent("parts"), persist: persist)
        for frame in frames.dropLast().dropLast() { XCTAssertNil(try inbox.receive(frame)) }
        XCTAssertEqual(try inbox.receive(frames[frames.count - 2]), frames.first?.recordingID)
        XCTAssertEqual(try Data(contentsOf: durable), data)
        XCTAssertEqual(try inbox.receive(frames[0]), frames[0].recordingID, "A late fallback/retry uses the saved receipt")
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        for frame in frames { XCTAssertLessThan(try encoder.encode(frame).count, 48 * 1_024) }
    }

    func testFailedPersistenceCannotProduceACompletionReceipt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try recording(), frames = try RecordingTransfer.frames(for: data)
        let broken = RecordingTransferInbox(directory: root) { _ in throw Failure.disk }
        for frame in frames.dropLast() { XCTAssertNil(try broken.receive(frame)) }
        XCTAssertThrowsError(try broken.receive(frames.last!))
        let recovered = RecordingTransferInbox(directory: root) { try $0.write(to: root.appendingPathComponent("durable.json")) }
        XCTAssertEqual(try recovered.receive(frames.last!), frames[0].recordingID)
    }

    func testWholeFileWinningRaceClearsPartsAndStopsLateFrames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try recording(), frames = try RecordingTransfer.frames(for: data)
        let inbox = RecordingTransferInbox(directory: root) { _ in throw Failure.disk }
        XCTAssertNil(try inbox.receive(frames[0]))
        // The file-transfer delegate saves these bytes before recording its receipt.
        try data.write(to: root.appendingPathComponent("file-lane.json"), options: .atomic)
        try inbox.recordWholeDelivery(data)
        XCTAssertEqual(try inbox.receive(frames.last!), frames[0].recordingID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".part") }.count, 0)
    }

    func testCorruptAndUnboundedFramesNeverAcknowledgeARecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let frames = try RecordingTransfer.frames(for: recording())
        let first = frames[0]
        let inbox = RecordingTransferInbox(directory: root) { _ in throw Failure.disk }
        let oversized = RecordingTransfer.Frame(recordingID: first.recordingID, digest: first.digest, index: 0, count: Int.max,
                                                totalBytes: Int.max, body: first.body)
        XCTAssertThrowsError(try inbox.receive(oversized))
        var corrupt = first.body; corrupt[0] ^= 1
        XCTAssertNil(try inbox.receive(.init(recordingID: first.recordingID, digest: first.digest, index: 0,
                                            count: first.count, totalBytes: first.totalBytes, body: corrupt)))
        for frame in frames.dropFirst().dropLast() { XCTAssertNil(try inbox.receive(frame)) }
        XCTAssertThrowsError(try inbox.receive(frames.last!))
    }

    private func recording() throws -> Data {
        let start = Date(timeIntervalSince1970: 1_700_000_000.125)
        var recording = MotionRecording(label: .unlabelled, startedAt: start)
        recording.samples = (0..<600).map {
            MotionSample(timestamp: start.addingTimeInterval(Double($0) * 0.1), gravity: .init(x: 0, y: 0, z: -1),
                         userAcceleration: .init(x: sin(Double($0)), y: 0, z: 0), rotationRate: .init(x: 0, y: 0.4, z: 0))
        }
        recording.endedAt = recording.samples.last?.timestamp
        return try JSONEncoder().encode(recording)
    }
}
