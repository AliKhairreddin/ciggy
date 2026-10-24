import Foundation

public struct MotionHistoryCheckpoint: Codable, Sendable {
    public let processedThrough: Date
    public let analyzer: RecordedMotionAnalyzer
    public let latestSampleAt: Date?
    public let pendingRanges: [MotionHistoryRange]?
    public let hasExpiredHistory: Bool?
    public let checkedAt: Date?
    public let backlogPending: Bool?
    public let replayCheckpoints: [MotionHistoryReplayCheckpoint]?
    public let sourceStartedAt: Date?

    public init(processedThrough: Date, analyzer: RecordedMotionAnalyzer, latestSampleAt: Date? = nil,
                pendingRanges: [MotionHistoryRange]? = nil, hasExpiredHistory: Bool? = nil,
                checkedAt: Date? = nil, backlogPending: Bool? = nil,
                replayCheckpoints: [MotionHistoryReplayCheckpoint]? = nil, sourceStartedAt: Date? = nil) {
        self.processedThrough = processedThrough; self.analyzer = analyzer
        self.latestSampleAt = latestSampleAt; self.pendingRanges = pendingRanges
        self.hasExpiredHistory = hasExpiredHistory; self.checkedAt = checkedAt
        self.backlogPending = backlogPending; self.replayCheckpoints = replayCheckpoints
        self.sourceStartedAt = sourceStartedAt
    }

    fileprivate var isValid: Bool {
        MotionHistoryProcessor.isSupportedDate(processedThrough) &&
        (sourceStartedAt.map { MotionHistoryProcessor.isSupportedDate($0) && $0 <= processedThrough } ?? true) &&
        (latestSampleAt.map(MotionHistoryProcessor.isSupportedDate) ?? true) &&
        (checkedAt.map(MotionHistoryProcessor.isSupportedDate) ?? true)
    }
}

/// Atomic history cursor, classifier, and source-origin storage. A corrupt
/// authoritative file must not silently fall back to an older cursor and count
/// past motion again. The prior complete snapshot stays in memory on write failure.
@MainActor
public final class MotionHistoryCheckpointStore {
    public private(set) var checkpoint: MotionHistoryCheckpoint?
    public private(set) var lastError: String?
    public private(set) var loadFailed = false
    private let snapshot: DurableSnapshotFile

    public init(userDefaults: UserDefaults = .standard,
                snapshotURL: URL = DurableSnapshotFile.defaultURL(name: "BackgroundMotionMonitor.checkpoint.v2")) {
        snapshot = DurableSnapshotFile(url: snapshotURL)
        do {
            if let data = try snapshot.load() {
                let loaded = try JSONDecoder().decode(MotionHistoryCheckpoint.self, from: data)
                guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
                checkpoint = loaded
            } else {
                let legacyOrigin = (userDefaults.object(forKey: "BackgroundMotionMonitor.processedThrough.v1") as? Date)
                    .flatMap { MotionHistoryProcessor.isSupportedDate($0) ? $0 : nil }
                if let data = userDefaults.data(forKey: "BackgroundMotionMonitor.checkpoint.v2") {
                    let loaded = try JSONDecoder().decode(MotionHistoryCheckpoint.self, from: data)
                    guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
                    checkpoint = .init(processedThrough: loaded.processedThrough, analyzer: loaded.analyzer,
                        latestSampleAt: loaded.latestSampleAt, pendingRanges: loaded.pendingRanges,
                        hasExpiredHistory: loaded.hasExpiredHistory, checkedAt: loaded.checkedAt,
                        backlogPending: loaded.backlogPending, replayCheckpoints: loaded.replayCheckpoints,
                        sourceStartedAt: loaded.sourceStartedAt ?? legacyOrigin.flatMap { $0 <= loaded.processedThrough ? $0 : nil })
                } else if let legacyOrigin {
                    checkpoint = .init(processedThrough: legacyOrigin, analyzer: .init(), sourceStartedAt: legacyOrigin)
                }
                if let checkpoint { _ = save(checkpoint) }
            }
        } catch {
            loadFailed = true
            lastError = "Could not read saved motion history progress. Tracking is paused to preserve previous counts."
        }
    }

    /// Persist the capture origin before arming the source for the first time.
    @discardableResult public func beginCapture(at now: Date) -> Bool {
        guard loadFailed == false else { return false }
        if checkpoint != nil { return true }
        return save(.init(processedThrough: now, analyzer: .init(), sourceStartedAt: now))
    }

    @discardableResult public func save(_ proposed: MotionHistoryCheckpoint) -> Bool {
        guard loadFailed == false else { return false }
        guard proposed.isValid,
              checkpoint.map({ proposed.processedThrough >= $0.processedThrough }) ?? true,
              checkpoint?.sourceStartedAt.map({ proposed.sourceStartedAt == $0 }) ?? true else {
            lastError = "Could not save invalid motion history progress."
            return false
        }
        do {
            try snapshot.write(JSONEncoder().encode(proposed))
            checkpoint = proposed
            lastError = nil
            return true
        } catch {
            lastError = "Could not save motion history progress. Ciggy will retry without advancing past unsaved data."
            return false
        }
    }
}
