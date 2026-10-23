import CryptoKit
import Foundation

/// Consent-scoped, acceleration-only calibration chunks. Source acceleration is
/// already measured in g by Core Motion; gyro is absent, never synthesized.
public enum HistoricalCalibrationSampler {
    public static let chunkSeconds: TimeInterval = 5 * 60
    public static let retentionSeconds: TimeInterval = 48 * 60 * 60
    public static let availabilityDelay: TimeInterval = 3 * 60
    public static let retrySeconds: TimeInterval = 60
    public static let maximumSamples = 3_000

    public struct Window: Codable, Equatable, Sendable {
        public let id: UUID
        public let start: Date
        public let end: Date

        fileprivate init(consent: Date, start: Date) {
            self.start = start
            end = start.addingTimeInterval(chunkSeconds)
            let key = "ciggy-calibration-history-v1:\(Int64(consent.timeIntervalSince1970 * 1_000)):\(Int64(start.timeIntervalSince1970 * 1_000))"
            var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
    }

    /// Completed IDs are the durable per-chunk cursor. Keeping them after a file
    /// is delivered or size-pruned avoids pulling unchanged history again.
    public struct Ledger: Codable, Sendable {
        public private(set) var enabledAt: Date
        public private(set) var completed: [UUID: Date] = [:]
        public private(set) var retryAfter: [UUID: Date] = [:]
        private var retryAttempts: [UUID: Int]?
        public private(set) var partialRecordingIDs: [UUID: UUID]?

        public init(enabledAt: Date) { self.enabledAt = enabledAt }

        public mutating func reconcile(consent: Date, now: Date) {
            guard valid(consent), valid(now) else { completed = [:]; retryAfter = [:]; return }
            if enabledAt != consent {
                enabledAt = consent
                completed = [:]
                retryAfter = [:]
                retryAttempts = [:]
                partialRecordingIDs = [:]
            }
            if retryAttempts == nil {
                // Migrate old fixed 15-minute retries without delaying first data.
                retryAfter = retryAfter.mapValues { min($0, now.addingTimeInterval(retrySeconds)) }
                retryAttempts = [:]
            }
            let eligible = windows(enabledAt: consent, now: now)
            let ids = Set(eligible.map(\.id))
            completed = completed.filter { ids.contains($0.key) && valid($0.value) }
            retryAfter = retryAfter.filter { ids.contains($0.key) && valid($0.value) }
            retryAttempts = retryAttempts?.filter { ids.contains($0.key) }
            partialRecordingIDs = partialRecordingIDs?.filter { ids.contains($0.key) }
        }

        public func pending(now: Date) -> [Window] {
            windows(enabledAt: enabledAt, now: now).filter {
                completed[$0.id] == nil && (retryAfter[$0.id].map { $0 <= now } ?? true)
            }
        }

        public mutating func didComplete(_ window: Window) {
            completed[window.id] = window.end
            retryAfter.removeValue(forKey: window.id)
            retryAttempts?.removeValue(forKey: window.id)
            partialRecordingIDs?.removeValue(forKey: window.id)
        }

        public mutating func retry(_ window: Window, after now: Date) {
            guard valid(now) else { return }
            var attempts = retryAttempts ?? [:]
            let count = min(5, (attempts[window.id] ?? 0) + 1)
            attempts[window.id] = count
            retryAttempts = attempts
            retryAfter[window.id] = now.addingTimeInterval(min(15 * 60, retrySeconds * pow(2, Double(count - 1))))
        }

        public mutating func didQueuePartial(_ recording: MotionRecording, for window: Window) {
            var ids = partialRecordingIDs ?? [:]
            ids[window.id] = recording.id
            partialRecordingIDs = ids
        }
    }

    public enum SamplingResult: Sendable {
        case complete(MotionRecording)
        case partial(MotionRecording)
        case missing
        case interrupted
    }

    /// Only whole five-minute windows at least three minutes old, strictly after
    /// consent and within 48h. Newest-first work prevents old backlog starvation.
    public static func windows(enabledAt: Date, now: Date) -> [Window] {
        guard valid(enabledAt), valid(now), enabledAt < now else { return [] }
        let cutoff = now.addingTimeInterval(-availabilityDelay)
        let retentionStart = now.addingTimeInterval(-retentionSeconds)
        let lower = max(enabledAt, retentionStart)
        let firstIndex = max(0, ceil(lower.timeIntervalSince(enabledAt) / chunkSeconds))
        let pastLastIndex = floor(cutoff.timeIntervalSince(enabledAt) / chunkSeconds)
        guard firstIndex.isFinite, pastLastIndex.isFinite, pastLastIndex > firstIndex,
              pastLastIndex - firstIndex <= 576 else { return [] }
        return stride(from: pastLastIndex - 1, through: firstIndex, by: -1).map {
            Window(consent: enabledAt, start: enabledAt.addingTimeInterval($0 * chunkSeconds))
        }
    }

    /// Usable fragments are saved with their gaps, while incomplete source
    /// intervals remain retryable. Cancellation never publishes partial iteration.
    public static func sample(
        _ input: AnySequence<RecordedAccelerationSample>,
        window: Window,
        enabledAt: Date,
        shouldContinue: () -> Bool = { true }
    ) -> SamplingResult {
        guard valid(enabledAt), valid(window.start), valid(window.end),
              window.start >= enabledAt,
              abs(window.end.timeIntervalSince(window.start) - chunkSeconds) < 0.001 else { return .missing }
        guard shouldContinue() else { return .interrupted }
        var output: [MotionSample] = []
        output.reserveCapacity(maximumSamples)
        var firstSourceAt: Date?
        var lastSourceAt: Date?
        var lastKeptAt: Date?
        var gravity: MotionVector?
        var count = 0
        var missing = false
        for raw in input {
            count += 1
            if count.isMultiple(of: 128), shouldContinue() == false { return .interrupted }
            guard valid(raw.timestamp), raw.timestamp >= window.start, raw.timestamp < window.end,
                  raw.timestamp >= enabledAt else { continue }
            let acceleration = MotionVector(x: raw.x, y: raw.y, z: raw.z)
            guard acceleration.isFinite, acceleration.magnitude.isFinite, acceleration.magnitude > 0.01 else {
                missing = true
                gravity = nil
                lastKeptAt = nil
                continue
            }
            if let previous = lastSourceAt {
                guard raw.timestamp > previous else { missing = true; continue }
                if raw.timestamp.timeIntervalSince(previous) > 1 {
                    missing = true
                    gravity = nil
                    lastKeptAt = nil
                }
            }
            if firstSourceAt == nil { firstSourceAt = raw.timestamp }
            lastSourceAt = raw.timestamp
            let elapsed = lastKeptAt.map { raw.timestamp.timeIntervalSince($0) } ?? 0.1
            guard elapsed >= 0.1 - 0.000_001 else { continue }
            // Sensor clock jitter may yield one extra 10Hz point. Decimation's
            // size cap must not turn an otherwise covered interval into a gap.
            guard output.count < maximumSamples else { continue }
            let weight = 1 - exp(-elapsed / 0.25)
            gravity = gravity?.blended(with: acceleration, weight: weight) ?? acceleration
            guard let gravity else { continue }
            output.append(MotionSample(
                timestamp: raw.timestamp, gravity: gravity,
                userAcceleration: .init(x: acceleration.x - gravity.x, y: acceleration.y - gravity.y,
                                        z: acceleration.z - gravity.z),
                rotationRate: nil, source: .recordedAccelerometer
            ))
            lastKeptAt = raw.timestamp
        }
        guard shouldContinue() else { return .interrupted }
        guard let firstSourceAt, let lastSourceAt, output.isEmpty == false else { return .missing }
        let complete = !missing && firstSourceAt.timeIntervalSince(window.start) <= 1 && window.end.timeIntervalSince(lastSourceAt) <= 1
        var id = window.id
        if !complete {
            // A later fuller query gets a different immutable ID and cannot
            // overwrite samples or labels already saved for this fragment.
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            guard let data = try? encoder.encode(output) else { return .missing }
            let key = Data(window.id.uuidString.utf8) + data
            var bytes = Array(SHA256.hash(data: key).prefix(16))
            bytes[6] = (bytes[6] & 0x0f) | 0x50
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        var recording = MotionRecording(id: id, label: .unlabelled, startedAt: window.start)
        recording.samples = output
        recording.endedAt = window.end
        return complete ? .complete(recording) : .partial(recording)
    }

    private static func valid(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }
}
