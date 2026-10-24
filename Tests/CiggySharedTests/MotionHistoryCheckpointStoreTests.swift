import XCTest
@testable import CiggyShared

@MainActor
final class MotionHistoryCheckpointStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testCaptureOriginAndProgressSurviveReopeningWithoutPreferences() throws {
        let (directory, url, defaults, name) = context()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        let store = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertTrue(store.beginCapture(at: start))
        let range = MotionHistoryRange(start: start, end: start.addingTimeInterval(500))
        let replay = MotionHistoryReplayCheckpoint(range: range, origin: start, processedThrough: start, analyzer: .init())
        let saved = MotionHistoryCheckpoint(processedThrough: start.addingTimeInterval(1_000), analyzer: .init(),
            pendingRanges: [range], hasExpiredHistory: true, backlogPending: true,
            replayCheckpoints: [replay], sourceStartedAt: start)
        XCTAssertTrue(store.save(saved))
        defaults.removePersistentDomain(forName: name)
        let reopened = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertEqual(reopened.checkpoint?.processedThrough, saved.processedThrough)
        XCTAssertEqual(reopened.checkpoint?.sourceStartedAt, start)
        XCTAssertEqual(reopened.checkpoint?.pendingRanges, [range])
        XCTAssertEqual(reopened.checkpoint?.replayCheckpoints?.first?.processedThrough, start)
        XCTAssertEqual(reopened.checkpoint?.hasExpiredHistory, true)
    }

    func testLegacyCheckpointMigratesOnlyWhenAuthoritativeFileIsAbsent() throws {
        let (directory, url, defaults, name) = context()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        let legacy = MotionHistoryCheckpoint(processedThrough: start.addingTimeInterval(500), analyzer: .init())
        defaults.set(start, forKey: "BackgroundMotionMonitor.processedThrough.v1")
        defaults.set(try JSONEncoder().encode(legacy), forKey: "BackgroundMotionMonitor.checkpoint.v2")
        let migrated = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertEqual(migrated.checkpoint?.processedThrough, legacy.processedThrough)
        XCTAssertEqual(migrated.checkpoint?.sourceStartedAt, start)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        defaults.set(start.addingTimeInterval(-1_000), forKey: "BackgroundMotionMonitor.processedThrough.v1")
        let reopened = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertEqual(reopened.checkpoint?.sourceStartedAt, start)
    }

    func testFailedSaveKeepsPriorCursorAndCanRetry() throws {
        let (directory, url, defaults, name) = context()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        let store = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertTrue(store.beginCapture(at: start))
        // Occupy the destination with a directory: atomic rename must fail.
        let backup = directory.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: url, to: backup)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let newer = MotionHistoryCheckpoint(processedThrough: start.addingTimeInterval(1_000), analyzer: .init(), sourceStartedAt: start)
        XCTAssertFalse(store.save(newer))
        XCTAssertEqual(store.checkpoint?.processedThrough, start)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(try JSONDecoder().decode(MotionHistoryCheckpoint.self, from: Data(contentsOf: backup)).processedThrough, start)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: backup, to: url)
        XCTAssertTrue(store.save(newer))
        XCTAssertNil(store.lastError)
        XCTAssertEqual(MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url).checkpoint?.processedThrough, newer.processedThrough)
    }

    func testCorruptAuthoritativeFileNeverFallsBackOrResetsCaptureOrigin() throws {
        let (directory, url, defaults, name) = context()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = Data("incomplete checkpoint".utf8)
        try corrupt.write(to: url)
        defaults.set(start, forKey: "BackgroundMotionMonitor.processedThrough.v1")
        let legacy = MotionHistoryCheckpoint(processedThrough: start, analyzer: .init(), sourceStartedAt: start)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "BackgroundMotionMonitor.checkpoint.v2")
        let store = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertTrue(store.loadFailed)
        XCTAssertNil(store.checkpoint)
        XCTAssertFalse(store.beginCapture(at: start.addingTimeInterval(5_000)))
        XCTAssertFalse(store.save(legacy))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testInvalidOrBackwardProgressCannotReplaceValidFile() throws {
        let (directory, url, defaults, name) = context()
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        let store = MotionHistoryCheckpointStore(userDefaults: defaults, snapshotURL: url)
        XCTAssertTrue(store.beginCapture(at: start))
        let original = try Data(contentsOf: url)
        XCTAssertFalse(store.save(.init(processedThrough: start.addingTimeInterval(-1), analyzer: .init(), sourceStartedAt: start)))
        XCTAssertFalse(store.save(.init(processedThrough: Date(timeIntervalSince1970: .nan), analyzer: .init(), sourceStartedAt: start)))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private func context() -> (URL, URL, UserDefaults, String) {
        let name = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (directory, directory.appendingPathComponent("history.json"), UserDefaults(suiteName: name)!, name)
    }
}
