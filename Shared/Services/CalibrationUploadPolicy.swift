import Foundation

/// Shared, deterministic checks before any raw recording leaves the iPhone.
public enum CalibrationUploadPolicy {
    public static let retention: TimeInterval = 48 * 3_600
    public static let maximumBytes = 5 * 1_024 * 1_024
    // Queue a bounded batch with the system, rather than requiring an app wake
    // after every two files. URLSession still limits network concurrency to two.
    public static let maximumScheduledFiles = 24
    public static let maximumScheduledBytes = 32 * 1_024 * 1_024

    public enum Eligibility: Equatable, Sendable {
        case eligible(expiresAt: Date)
        case beforeConsent
        case expired
        case invalid
    }

    public static func recordingID(filename: String) -> UUID? {
        guard filename.hasPrefix("motion-"), filename.hasSuffix(".json"),
              filename.count == 7 + 36 + 5 else { return nil }
        return UUID(uuidString: String(filename.dropFirst(7).dropLast(5)))
    }

    public static func eligibility(
        _ recording: MotionRecording, filename: String, consent: Date, now: Date
    ) -> Eligibility {
        guard valid(consent), valid(now), consent <= now,
              recordingID(filename: filename) == recording.id, recording.formatVersion == 1,
              valid(recording.startedAt), (1...18_000).contains(recording.samples.count),
              let first = recording.samples.first, let last = recording.samples.last else { return .invalid }
        guard recording.startedAt >= consent,
              recording.samples.allSatisfy({ valid($0.timestamp) && $0.timestamp >= consent }) else { return .beforeConsent }
        guard recording.startedAt >= now.addingTimeInterval(-retention),
              recording.samples.allSatisfy({ $0.timestamp >= now.addingTimeInterval(-retention) }) else { return .expired }
        let endedAt = recording.endedAt ?? last.timestamp
        guard valid(endedAt), endedAt >= last.timestamp, endedAt <= now,
              endedAt.timeIntervalSince(recording.startedAt) <= 601,
              first.timestamp >= recording.startedAt.addingTimeInterval(-1),
              last.timestamp.timeIntervalSince(first.timestamp) <= 601 else { return .invalid }
        var previous: Date?
        for sample in recording.samples {
            guard sample.isValid, sample.timestamp <= endedAt,
                  previous.map({ sample.timestamp > $0 }) ?? true,
                  sample.gravity.magnitude <= 4, sample.userAcceleration.magnitude <= 64,
                  sample.rotationRate.map({ $0.magnitude <= 100 }) ?? true,
                  sample.source != .recordedAccelerometer || sample.rotationRate == nil else { return .invalid }
            previous = sample.timestamp
        }
        return .eligible(expiresAt: min(recording.startedAt, first.timestamp).addingTimeInterval(retention))
    }

    public static func receiptMatches(_ data: Data, filename: String) -> Bool {
        struct Receipt: Decodable { let recordingID: UUID }
        guard let expected = recordingID(filename: filename),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else { return false }
        return receipt.recordingID == expected
    }

    /// Kept across launches, including a provider-wide pause after 429/503 so a
    /// new recording cannot bypass Retry-After by having a different filename.
    public struct Backoff: Codable, Sendable {
        public struct Failure: Codable, Sendable {
            public let attempts: Int
            public let nextAttemptAt: Date
        }
        public private(set) var failures: [String: Failure] = [:]
        public private(set) var providerRetryAt: Date?
        public init() {}

        public func allows(_ filename: String, at now: Date) -> Bool {
            guard valid(now) else { return false }
            return (providerRetryAt.map { valid($0) && $0 <= now } ?? true) &&
                (failures[filename].map { valid($0.nextAttemptAt) && $0.nextAttemptAt <= now } ?? true)
        }

        /// Hand the retry deadline to URLSession instead of depending on a later
        /// foreground launch to notice that an in-memory cooldown has elapsed.
        public func nextAttempt(for filename: String, at now: Date) -> Date {
            [now, providerRetryAt, failures[filename]?.nextAttemptAt]
                .compactMap { $0 }.filter(valid).max() ?? now
        }

        public mutating func failed(_ filename: String, status: Int?, retryAfter: String?, at now: Date) {
            guard recordingID(filename: filename) != nil, valid(now) else { return }
            let attempt = min(8, min(8, max(0, failures[filename]?.attempts ?? 0)) + 1)
            let exponential = now.addingTimeInterval(min(3_600, pow(2, Double(attempt)) * 30))
            let next = max(exponential, retryDate(retryAfter, now: now) ?? now)
            failures[filename] = .init(attempts: attempt, nextAttemptAt: next)
            if status == 429 || status == 503 { providerRetryAt = max(providerRetryAt ?? now, next) }
        }

        public mutating func succeeded(_ filename: String) { failures.removeValue(forKey: filename) }

        public mutating func prune(keeping filenames: Set<String>, at now: Date) {
            failures = failures.filter {
                filenames.contains($0.key) && recordingID(filename: $0.key) != nil &&
                (1...8).contains($0.value.attempts) && valid($0.value.nextAttemptAt)
            }
            if let providerRetryAt, valid(providerRetryAt) == false || providerRetryAt <= now { self.providerRetryAt = nil }
        }
    }

    public static func retryDate(_ value: String?, now: Date) -> Date? {
        guard valid(now), let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count <= 100 else { return nil }
        if let seconds = Double(raw), seconds.isFinite, seconds >= 0,
           seconds <= Date.distantFuture.timeIntervalSince(now) {
            return now.addingTimeInterval(seconds)
        }
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: raw), valid(date) { return max(now, date) }
        }
        return nil
    }

    private static func valid(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }
}
