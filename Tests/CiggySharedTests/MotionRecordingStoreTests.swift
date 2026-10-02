import XCTest
@testable import CiggyShared

@MainActor
final class MotionRecordingStoreTests: XCTestCase {
    func testOptInRecordingCanBeReplayedWithSubsecondSensorTimestamps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MotionRecordingStore(directory: directory)
        let start = Date()
        let samples = MotionFixtures.cycle(start: start)
        store.append(samples[0])
        XCTAssertFalse(store.isRecording)
        store.start(label: .smokingGesture)
        samples.forEach { store.append($0) }
        let url = try XCTUnwrap(store.finishIfRecording())
        let recording = try JSONDecoder().decode(MotionRecording.self, from: Data(contentsOf: url))
        XCTAssertEqual(recording.label, .smokingGesture)
        XCTAssertEqual(recording.samples, samples)
        var engine = MotionGestureEngine()
        XCTAssertEqual(recording.samples.compactMap { engine.record($0) }.count, 1)
        try store.deleteRecordings()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordingStopsAtDurationLimit() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MotionRecordingStore(directory: directory)
        store.start(duration: 1)
        store.append(MotionFixtures.sample(start: Date(), seconds: 2, angle: 0))
        XCTAssertFalse(store.isRecording)
        XCTAssertNotNil(store.latestRecordingURL)
    }

    func testImportValidatesRecordingAndPreservesItsIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MotionRecordingStore(directory: directory)
        var recording = MotionRecording(label: .drinking)
        recording.samples = MotionFixtures.cycle(start: Date())
        let data = try JSONEncoder().encode(recording)
        let first = try store.importRecording(data: data)
        let duplicate = try store.importRecording(data: data)
        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(try JSONDecoder().decode(MotionRecording.self, from: Data(contentsOf: first)).samples, recording.samples)
        recording.samples = recording.samples.reversed()
        XCTAssertThrowsError(try store.importRecording(data: JSONEncoder().encode(recording)))
        recording.samples = []
        XCTAssertThrowsError(try store.importRecording(data: JSONEncoder().encode(recording)))
    }

    func testReceivedFileSurvivesDelegateReturnAndInterruptedImport() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let inbox = base.appendingPathComponent("inbox")
        let directory = base.appendingPathComponent("recordings")
        var recording = MotionRecording(label: .other)
        recording.samples = MotionFixtures.cycle(start: Date())
        try MotionRecordingStore.preserveIncomingRecording(data: JSONEncoder().encode(recording), inboxDirectory: inbox)
        let relaunched = MotionRecordingStore(directory: directory)
        relaunched.recoverIncomingRecordings(from: inbox)
        let url = try XCTUnwrap(relaunched.latestRecordingURL)
        XCTAssertEqual(try JSONDecoder().decode(MotionRecording.self, from: Data(contentsOf: url)).samples, recording.samples)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).isEmpty)
        XCTAssertEqual(MotionRecordingStore(directory: directory).latestRecordingURL?.resolvingSymlinksInPath(),
                       url.resolvingSymlinksInPath())
    }
}
