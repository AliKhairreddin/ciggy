import CryptoKit
import Foundation

/// Raw calibration files wait for an hourly batch. Cigarette events and settings
/// use their independent, immediate transport and never consult this schedule.
public struct CalibrationTransferSchedule: Codable, Equatable, Sendable {
    public static let interval: TimeInterval = 60 * 60
    public private(set) var nextBatchAt: Date?
    public private(set) var releasedPaths: Set<String> = []
    public private(set) var lastBatchAt: Date?

    public init() {}

    public mutating func reconcile(pending: [String], at now: Date, oldestRecordingAt: Date? = nil) {
        releasedPaths.formIntersection(pending)
        if pending.isEmpty { nextBatchAt = nil }
        else {
            let oldest = min(now, oldestRecordingAt ?? now)
            let due = max(oldest.addingTimeInterval(Self.interval), lastBatchAt?.addingTimeInterval(Self.interval) ?? .distantPast)
            nextBatchAt = min(nextBatchAt ?? due, due)
        }
    }

    public mutating func releaseIfDue(pending: [String], at now: Date, oldestRecordingAt: Date? = nil) {
        reconcile(pending: pending, at: now, oldestRecordingAt: oldestRecordingAt)
        guard let nextBatchAt, now >= nextBatchAt else { return }
        releasedPaths.formUnion(pending)
        lastBatchAt = now
        self.nextBatchAt = now.addingTimeInterval(Self.interval)
    }

    public mutating func relocatePaths(_ mapping: [String: String]) {
        releasedPaths = Set(releasedPaths.map { mapping[$0] ?? $0 })
    }
}

/// App-container UUIDs can change on update. Only our own calibration filenames
/// may be relocated; arbitrary paths must never be imported into this outbox.
public enum CalibrationRecordingPath {
    public static func relocate(_ path: String, directory: URL) -> String {
        let old = URL(fileURLWithPath: path)
        guard old.deletingLastPathComponent().lastPathComponent == "CiggyHistoricalCalibration",
              endDate(filename: old.lastPathComponent) != nil else { return path }
        return directory.appendingPathComponent(old.lastPathComponent).path
    }

    public static func endDate(filename: String) -> Date? {
        guard filename.hasSuffix(".json") else { return nil }
        let fields = filename.dropLast(5).split(separator: "_", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "calibration", let milliseconds = Double(fields[1]),
              milliseconds.isFinite, milliseconds >= 0, milliseconds < 32_503_680_000_000,
              UUID(uuidString: String(fields[2])) != nil else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

/// Small acknowledged messages supplement the durable WC file transfer. The
/// original file stays queued until the complete bytes are saved on iPhone.
public enum RecordingTransfer {
    public static let frameBytes = 40 * 1_024
    public static let maximumBytes = 2 * 1_024 * 1_024
    public enum TransferError: Error { case invalid, full }

    public struct Frame: Codable, Sendable {
        public let recordingID: UUID
        public let digest: String
        public let index: Int
        public let count: Int
        public let totalBytes: Int
        public let body: Data

        public init(recordingID: UUID, digest: String, index: Int, count: Int, totalBytes: Int, body: Data) {
            self.recordingID = recordingID; self.digest = digest; self.index = index
            self.count = count; self.totalBytes = totalBytes; self.body = body
        }
    }

    public static func frames(for data: Data) throws -> [Frame] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw TransferError.invalid }
        let recording = try MotionRecordingStore.decodeValidatedRecording(data)
        let digest = hash(data), count = (data.count + frameBytes - 1) / frameBytes
        return (0..<count).map { index in
            Frame(recordingID: recording.id, digest: digest, index: index, count: count,
                  totalBytes: data.count, body: data.subdata(in: (index * frameBytes)..<min(data.count, (index + 1) * frameBytes)))
        }
    }

    fileprivate static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Disk-backed reassembly survives a phone launch between messages. Receipts
/// are returned only after validation and atomic persistence of the whole file.
public final class RecordingTransferInbox: @unchecked Sendable {
    private let directory: URL
    private let persist: @Sendable (Data) throws -> Void
    private let lock = NSLock()
    private struct Manifest: Codable {
        let recordingID: UUID
        let digest: String
        let count: Int
        let totalBytes: Int
        let createdAt: Date
    }
    private struct Receipt: Codable { let recordingID: UUID; let savedAt: Date }

    private func receipts(at now: Date) -> [String: Receipt] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("receipts.json")), data.count <= 512 * 1_024,
              let saved = try? JSONDecoder().decode([String: Receipt].self, from: data) else { return [:] }
        return saved.filter { now.timeIntervalSince($0.value.savedAt) < 24 * 3_600 && $0.value.savedAt <= now }
    }

    private func remember(_ recordingID: UUID, digest: String, at now: Date) throws {
        var saved = receipts(at: now)
        saved[digest] = Receipt(recordingID: recordingID, savedAt: now)
        if saved.count > 2_000 {
            let keys = saved.keys.sorted { saved[$0]!.savedAt > saved[$1]!.savedAt }.prefix(2_000)
            saved = saved.filter { keys.contains($0.key) }
        }
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("receipts.json"), options: .atomic)
    }

    /// The durable file lane can finish first. Its saved bytes satisfy the same
    /// receipt and let late fast frames stop without leaving orphaned pieces.
    public func recordWholeDelivery(_ data: Data, at now: Date = Date()) throws {
        guard data.count <= RecordingTransfer.maximumBytes else { return }
        let recording = try MotionRecordingStore.decodeValidatedRecording(data)
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = RecordingTransfer.hash(data)
        try remember(recording.id, digest: digest, at: now)
        let folder = directory.appendingPathComponent("\(recording.id.uuidString).\(digest)", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    public init(directory: URL? = nil, persist: @escaping @Sendable (Data) throws -> Void = {
        try MotionRecordingStore.preserveIncomingRecording(data: $0)
    }) {
        self.directory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("CiggyFastMotionInbox", isDirectory: true)
        self.persist = persist
    }

    /// nil acknowledges a saved part; a UUID acknowledges a saved full recording.
    public func receive(_ frame: RecordingTransfer.Frame, at now: Date = Date()) throws -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard frame.totalBytes > 0, frame.totalBytes <= RecordingTransfer.maximumBytes,
              frame.count == (frame.totalBytes + RecordingTransfer.frameBytes - 1) / RecordingTransfer.frameBytes,
              (0..<frame.count).contains(frame.index), frame.digest.count == 64,
              frame.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              frame.body.count == min(RecordingTransfer.frameBytes, frame.totalBytes - frame.index * RecordingTransfer.frameBytes)
        else { throw RecordingTransfer.TransferError.invalid }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if receipts(at: now)[frame.digest]?.recordingID == frame.recordingID { return frame.recordingID }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var root = directory; try root.setResourceValues(values)
        let entries = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > 24 * 3_600 { try manager.removeItem(at: entry) }
        }
        let folder = directory.appendingPathComponent("\(frame.recordingID.uuidString).\(frame.digest)", isDirectory: true)
        if !manager.fileExists(atPath: folder.path) {
            let folders = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            guard folders.count < 8 else { throw RecordingTransfer.TransferError.full }
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = Manifest(recordingID: frame.recordingID, digest: frame.digest, count: frame.count,
                                    totalBytes: frame.totalBytes, createdAt: now)
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.recordingID == frame.recordingID, manifest.digest == frame.digest,
              manifest.count == frame.count, manifest.totalBytes == frame.totalBytes else { throw RecordingTransfer.TransferError.invalid }
        let part = folder.appendingPathComponent("\(frame.index).part")
        if manager.fileExists(atPath: part.path) {
            guard try Data(contentsOf: part) == frame.body else { throw RecordingTransfer.TransferError.invalid }
        } else {
            try frame.body.write(to: part, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let parts = (0..<frame.count).map { folder.appendingPathComponent("\($0).part") }
        guard parts.allSatisfy({ manager.fileExists(atPath: $0.path) }) else { return nil }
        var complete = Data(); complete.reserveCapacity(frame.totalBytes)
        for part in parts {
            let data = try Data(contentsOf: part)
            guard complete.count + data.count <= frame.totalBytes else { throw RecordingTransfer.TransferError.invalid }
            complete.append(data)
        }
        guard complete.count == frame.totalBytes, RecordingTransfer.hash(complete) == frame.digest,
              try MotionRecordingStore.decodeValidatedRecording(complete).id == frame.recordingID else { throw RecordingTransfer.TransferError.invalid }
        try persist(complete)
        try remember(frame.recordingID, digest: frame.digest, at: now)
        try manager.removeItem(at: folder)
        return frame.recordingID
    }
}
