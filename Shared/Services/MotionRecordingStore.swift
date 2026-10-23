import Foundation
import Combine

public struct MotionRecording: Codable, Sendable {
    public enum Label: String, Codable, Sendable { case smokingGesture, eating, drinking, other, unlabelled }
    public let id: UUID
    public let startedAt: Date
    public let label: Label
    public var samples: [MotionSample]
    public var endedAt: Date?
    public let formatVersion: Int
    public init(id: UUID = UUID(), label: Label, startedAt: Date = Date()) {
        self.id = id; self.startedAt = startedAt; self.label = label
        samples = []; formatVersion = 1
    }
}

/// Opt-in, bounded recordings for real-device calibration and deterministic replay.
/// Raw samples stay in the app's private storage until explicitly exported.
@MainActor
public final class MotionRecordingStore: ObservableObject {
	public enum RecordingError: Error { case invalidRecording }
    public static let shared = MotionRecordingStore()
    @Published public private(set) var isRecording = false
    @Published public private(set) var sampleCount = 0
    @Published public private(set) var latestRecordingURL: URL?
    @Published public private(set) var lastError: String?
    public let completedRecording = PassthroughSubject<URL, Never>()
    private var recording: MotionRecording?
    private var duration: TimeInterval = 5 * 60
    private let maximumSamples = 18_000
    private let directory: URL
    private let usesDefaultDirectory: Bool

    public init(directory: URL? = nil) {
        usesDefaultDirectory = directory == nil
        self.directory = directory ?? Self.storageDirectory
            .appendingPathComponent("CiggyMotionRecordings", isDirectory: true)
        latestRecordingURL = (try? FileManager.default.contentsOfDirectory(at: self.directory,
            includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "json" }
            .max { a, b in
                let first = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let second = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return first < second
            }
        if directory == nil { recoverIncomingRecordings() }
    }

    /// WC deletes its temporary file when the delegate returns. Atomically save
    /// the bytes before that return, even when the app has no foreground runtime.
    public nonisolated static func preserveIncomingRecording(data: Data, inboxDirectory: URL? = nil) throws {
        guard data.count <= 10 * 1_024 * 1_024 else { throw RecordingError.invalidRecording }
        let inbox = inboxDirectory ?? incomingDirectory
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try data.write(to: inbox.appendingPathComponent("\(UUID().uuidString).json"), options: .atomic)
    }

    private nonisolated static var incomingDirectory: URL {
        storageDirectory
            .appendingPathComponent("CiggyMotionInbox", isDirectory: true)
    }

    private nonisolated static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    public func recoverIncomingRecordings(from inboxDirectory: URL? = nil) {
        let inbox = inboxDirectory ?? Self.incomingDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [] {
            do {
                try importRecording(data: Data(contentsOf: url))
                try FileManager.default.removeItem(at: url)
            } catch {
                lastError = "Could not import a received motion recording."
            }
        }
    }

    public func start(label: MotionRecording.Label = .unlabelled, duration: TimeInterval = 5 * 60) {
        guard isRecording == false else { return }
        self.duration = duration.isFinite ? max(1, min(10 * 60, duration)) : 5 * 60
        recording = MotionRecording(label: label)
        sampleCount = 0; lastError = nil; isRecording = true
    }

    public func append(_ sample: MotionSample) {
        guard recording != nil, sample.isValid else { return }
        if let last = recording?.samples.last, sample.timestamp <= last.timestamp { return }
        recording?.samples.append(sample)
        guard let count = recording?.samples.count, let startedAt = recording?.startedAt else { return }
        // Avoid publishing on every sensor callback.
        if count % 30 == 0 { sampleCount = count }
        if count >= maximumSamples || sample.timestamp.timeIntervalSince(startedAt) >= duration { finishIfRecording() }
    }

    @discardableResult
    public func finishIfRecording() -> URL? {
        guard var recording else { return nil }
        self.recording = nil; isRecording = false; sampleCount = recording.samples.count
        guard recording.samples.isEmpty == false else { return nil }
        recording.endedAt = recording.samples.last?.timestamp
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("motion-\(recording.id.uuidString).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            // Default date encoding preserves subsecond sensor timing during replay.
            try encoder.encode(recording).write(to: url, options: .atomic)
            latestRecordingURL = url; lastError = nil
            completedRecording.send(url)
            return url
        } catch { lastError = error.localizedDescription; return nil }
    }

    public func deleteRecordings() throws {
        recording = nil; isRecording = false; sampleCount = 0
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        if usesDefaultDirectory, FileManager.default.fileExists(atPath: Self.incomingDirectory.path) {
            try FileManager.default.removeItem(at: Self.incomingDirectory)
        }
        latestRecordingURL = nil
    }

    public func savedRecordingURLs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    public func removeRecording(at url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: url)
        if latestRecordingURL == url { latestRecordingURL = nil }
    }

    /// Called after WatchConnectivity has copied a file out of its temporary inbox.
    /// Filenames come from a validated UUID, never the sender's path.
    @discardableResult
    public func importRecording(data: Data) throws -> URL {
        guard data.count <= 10 * 1_024 * 1_024 else { throw RecordingError.invalidRecording }
        let imported = try JSONDecoder().decode(MotionRecording.self, from: data)
        guard imported.formatVersion == 1, imported.samples.isEmpty == false,
              imported.samples.count <= maximumSamples, imported.samples.allSatisfy(\.isValid),
              imported.startedAt.timeIntervalSince1970.isFinite,
              imported.startedAt >= .distantPast, imported.startedAt <= .distantFuture,
              let first = imported.samples.first, let last = imported.samples.last,
              first.timestamp >= imported.startedAt.addingTimeInterval(-1),
              last.timestamp <= imported.startedAt.addingTimeInterval(601),
              last.timestamp.timeIntervalSince(first.timestamp) <= 601 else {
            throw RecordingError.invalidRecording
        }
        if let endedAt = imported.endedAt {
            guard endedAt.timeIntervalSince1970.isFinite, endedAt >= last.timestamp,
                  endedAt.timeIntervalSince(imported.startedAt) <= 601 else {
                throw RecordingError.invalidRecording
            }
        }
        for index in 1..<imported.samples.count where imported.samples[index].timestamp <= imported.samples[index - 1].timestamp {
            throw RecordingError.invalidRecording
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("motion-\(imported.id.uuidString).json")
        try data.write(to: url, options: .atomic)
        latestRecordingURL = url
        lastError = nil
        return url
    }
}
