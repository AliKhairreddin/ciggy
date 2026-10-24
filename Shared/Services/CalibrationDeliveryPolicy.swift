import Foundation

/// A queued diagnostic is not a server receipt. Failures get a persisted retry
/// deadline that URLSession can honor without another foreground launch.
public struct CalibrationDeliveryPolicy: Codable, Sendable {
    public private(set) var lastSucceededAt: Date?
    public private(set) var retryAt: Date?
    public private(set) var failures = 0

    public init() {}

    public func shouldSchedule(at now: Date) -> Bool {
        guard MotionHistoryProcessor.isSupportedDate(now) else { return false }
        if failures > 0 { return true }
        return lastSucceededAt.map { $0 > now || now.timeIntervalSince($0) >= 30 * 60 } ?? true
    }

    public func earliestBeginDate(at now: Date, providerRetryAt: Date?) -> Date {
        [now, retryAt, providerRetryAt].compactMap { $0 }
            .filter(MotionHistoryProcessor.isSupportedDate).max() ?? now
    }

    public mutating func succeeded(at now: Date) {
        lastSucceededAt = now
        retryAt = nil
        failures = 0
    }

    public mutating func failed(at now: Date, retryAfter: String?) {
        failures = min(8, max(0, min(8, failures)) + 1)
        retryAt = max(now.addingTimeInterval(min(3_600, pow(2, Double(failures)) * 30)),
                      CalibrationUploadPolicy.retryDate(retryAfter, now: now) ?? now)
    }

    public static func receiptMatches(_ data: Data) -> Bool {
        struct Receipt: Decodable { let saved: Bool }
        return (try? JSONDecoder().decode(Receipt.self, from: data).saved) == true
    }
}
