import Foundation

/// Only delivery metadata for the opt-in motion workspace. No cigarette events,
/// HealthKit values, device identifiers, credentials, or free-form error text.
public struct CalibrationDeliveryReport: Encodable, Sendable {
    public let kind = "deliveryStatus"
    public let observedAt: Date
    public let consentAt: Date
    public let phoneBuild: String
    public let phoneLastReceivedAt: Date?
    public let phoneLastUploadedAt: Date?
    public let phonePendingCount: Int
    public let phoneScheduledCount: Int
    public let phoneRetryAt: Date?
    public let watch: Watch?

    public struct Watch: Codable, Sendable {
        public let checkedAt: Date?
        public let latestQueuedMotionAt: Date?
        public let queuedTransferCount: Int
        public let pendingWindowCount: Int
        public let nextBatchAt: Date?
        public let lastBatchAt: Date?
        public let lastDeliveredAt: Date?
        public let build: String?
    }

    public init(observedAt: Date, consentAt: Date, phoneBuild: String,
                phoneLastReceivedAt: Date?, phoneLastUploadedAt: Date?, phonePendingCount: Int,
                phoneScheduledCount: Int, phoneRetryAt: Date?, watchStatus: CalibrationTrackingStatus?) {
        self.observedAt = observedAt; self.consentAt = consentAt; self.phoneBuild = phoneBuild
        self.phoneLastReceivedAt = phoneLastReceivedAt; self.phoneLastUploadedAt = phoneLastUploadedAt
        self.phonePendingCount = max(0, phonePendingCount); self.phoneScheduledCount = max(0, phoneScheduledCount)
        self.phoneRetryAt = phoneRetryAt
        if let status = watchStatus, let enabledAt = status.enabledAt,
           abs(enabledAt.timeIntervalSince(consentAt)) < 1, status.hasValidDates {
            watch = Watch(checkedAt: status.checkedAt, latestQueuedMotionAt: status.latestQueuedMotionAt,
                queuedTransferCount: status.queuedTransferCount, pendingWindowCount: status.pendingWindowCount,
                nextBatchAt: status.nextBatchAt, lastBatchAt: status.lastBatchAt,
                lastDeliveredAt: status.lastDeliveredAt, build: status.build)
        } else { watch = nil }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }
}
