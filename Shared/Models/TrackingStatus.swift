import Combine
import Foundation

public struct CalibrationTrackingStatus: Codable, Equatable, Sendable {
    public let enabledAt: Date?
    public let checkedAt: Date?
    public let latestQueuedMotionAt: Date?
    public let pendingWindowCount: Int
    public let retryingWindowCount: Int
    public let queuedTransferCount: Int
    public let lastError: String?

    public init(enabledAt: Date?, checkedAt: Date?, latestQueuedMotionAt: Date?,
                pendingWindowCount: Int, retryingWindowCount: Int, queuedTransferCount: Int, lastError: String?) {
        self.enabledAt = enabledAt; self.checkedAt = checkedAt; self.latestQueuedMotionAt = latestQueuedMotionAt
        self.pendingWindowCount = max(0, pendingWindowCount); self.retryingWindowCount = max(0, retryingWindowCount)
        self.queuedTransferCount = max(0, queuedTransferCount); self.lastError = lastError
    }

    public var hasValidDates: Bool {
        [enabledAt, checkedAt, latestQueuedMotionAt].compactMap { $0 }.allSatisfy(MotionHistoryProcessor.isSupportedDate)
    }

    public func detail(consent: Date, now: Date = Date()) -> String {
        guard let enabledAt, abs(enabledAt.timeIntervalSince(consent)) < 0.01 else {
            return "Waiting for your Watch to receive the sharing setting."
        }
        if let lastError { return lastError }
        if queuedTransferCount > 0 { return "Watch last reported \(queuedTransferCount) saved recordings queued for hourly background delivery to this iPhone." }
        if let latestQueuedMotionAt {
            return "Watch saved motion through \(latestQueuedMotionAt.formatted(date: .omitted, time: .shortened)). Background history can still arrive later."
        }
        if retryingWindowCount > 0 { return "Waiting for recorded Watch motion. Available fragments are shared while missing intervals retry." }
        if now.timeIntervalSince(consent) < 8 * 60 {
            return "Waiting for the first saved motion. Calibration is sent in hourly batches when watchOS allows; cigarette counts sync independently."
        }
        return "No Watch recording has reached the transfer queue yet. Check that the Watch has Motion & Fitness permission and Ciggy is installed."
    }
}

/// The Watch's observation timestamps, not a claim of uninterrupted coverage.
public struct TrackingStatus: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let historyCheckedAt: Date?
    public let historySampleAt: Date?
    public let captureUntil: Date?
    public let pendingHistory: Bool
    public let expiredHistory: Bool
    public let captureAvailable: Bool
    public let permissionGranted: Bool
    public let lastError: String?
    public let isProcessing: Bool
    public let calibration: CalibrationTrackingStatus?

    public init(generatedAt: Date = Date(), historyCheckedAt: Date? = nil, historySampleAt: Date? = nil,
                captureUntil: Date? = nil, pendingHistory: Bool = false, expiredHistory: Bool = false,
                captureAvailable: Bool, permissionGranted: Bool, lastError: String? = nil,
                isProcessing: Bool = false, calibration: CalibrationTrackingStatus? = nil) {
        self.generatedAt = generatedAt
        self.historyCheckedAt = historyCheckedAt
        self.historySampleAt = historySampleAt
        self.captureUntil = captureUntil
        self.pendingHistory = pendingHistory
        self.expiredHistory = expiredHistory
        self.captureAvailable = captureAvailable
        self.permissionGranted = permissionGranted
        self.lastError = lastError
        self.isProcessing = isProcessing
        self.calibration = calibration
    }

    public var hasValidDates: Bool {
        [generatedAt, historyCheckedAt, historySampleAt, captureUntil].compactMap { $0 }
            .allSatisfy(MotionHistoryProcessor.isSupportedDate) && (calibration?.hasValidDates ?? true)
    }

    public func transferData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func fromTransfer(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Self.self, from: data)
    }

    public func title(at now: Date = Date()) -> String {
        if !captureAvailable { return "Watch motion unavailable" }
        if !permissionGranted { return "Motion permission needed" }
        if isProcessing && now.timeIntervalSince(generatedAt) < 60 { return "Checking Watch motion…" }
        if lastError != nil { return "Watch tracking needs attention" }
        if captureUntil.map({ $0 <= now }) ?? true { return "Watch recording needs renewal" }
        if let sample = historySampleAt, now.timeIntervalSince(sample) <= 10 * 60 {
            return pendingHistory ? "Recent motion checked · gaps pending" : "Recent Watch motion checked"
        }
        return "Recent Watch data pending"
    }

    public func detail(at now: Date = Date()) -> String {
        if !captureAvailable { return "Automatic tracking needs a physical Apple Watch with motion recording support." }
        if !permissionGranted { return "Allow Motion & Fitness access on your Watch to record activity while Ciggy is closed." }
        if let lastError { return "\(lastError) Your saved cigarettes are kept; recent totals may be incomplete." }
        var parts: [String] = []
        if let sample = historySampleAt {
            let format: Date.FormatStyle = Calendar.current.isDate(sample, inSameDayAs: now)
                ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day().hour().minute()
            parts.append("Latest recorded motion: \(sample.formatted(format)).")
        } else {
            parts.append("Waiting for the first recorded Watch motion.")
        }
        if captureUntil.map({ $0 <= now }) ?? true {
            parts.append("Background recording needs renewal on the Watch; some activity may be missing.")
        } else if historySampleAt.map({ now.timeIntervalSince($0) > 10 * 60 }) ?? true {
            parts.append("Recent cigarettes may not be included yet. A Watch check is requested when you open the iPhone app; delivery depends on watchOS.")
        } else {
            parts.append("The newest few minutes can still arrive later. Counts are motion estimates.")
        }
        if pendingHistory { parts.append("Some unavailable history is being retried.") }
        if expiredHistory { parts.append("Some older history expired before it could be checked.") }
        return parts.joined(separator: " ")
    }
}

/// Persist freshness across launches, and reject delayed older status deliveries.
@MainActor
public final class TrackingStatusStore: ObservableObject {
    public static let shared = TrackingStatusStore()
    @Published public private(set) var status: TrackingStatus?
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "Ciggy.trackingStatus.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(TrackingStatus.self, from: data), decoded.hasValidDates {
            status = decoded
        }
    }

    @discardableResult
    public func receive(_ incoming: TrackingStatus) -> Bool {
        guard incoming.hasValidDates, status.map({ incoming.generatedAt > $0.generatedAt }) ?? true else { return false }
        guard let data = try? JSONEncoder().encode(incoming) else { return false }
        defaults.set(data, forKey: key)
        status = incoming
        return true
    }
}

public struct HistoryRefreshRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let requestedAt: Date
    public init(id: UUID = UUID(), requestedAt: Date = Date()) {
        self.id = id
        self.requestedAt = requestedAt
    }
}

/// Opening a screen repeatedly must not flood the Watch's background queue.
public enum HistoryRefreshPolicy {
    public static func shouldRequest(at now: Date, lastRequestedAt: Date?, minimumInterval: TimeInterval = 60) -> Bool {
        guard MotionHistoryProcessor.isSupportedDate(now) else { return false }
        guard let lastRequestedAt, MotionHistoryProcessor.isSupportedDate(lastRequestedAt) else { return true }
        let elapsed = now.timeIntervalSince(lastRequestedAt)
        return elapsed < 0 || elapsed >= minimumInterval
    }
}
