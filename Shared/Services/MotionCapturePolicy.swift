import Foundation

/// Keep the existing earlier background appointment: watchOS has one slot and
/// scheduling another task replaces it. Frequent app opens must not slide it later.
public enum MotionCapturePolicy {
    public static func shouldRenew(at now: Date, armedUntil: Date?) -> Bool {
        guard let armedUntil, MotionHistoryProcessor.isSupportedDate(armedUntil) else { return true }
        return armedUntil.timeIntervalSince(now) <= 6 * 60 * 60
    }

    public static func shouldSchedule(at now: Date, existing: Date?, preferred: Date) -> Bool {
        guard let existing, MotionHistoryProcessor.isSupportedDate(existing) else { return true }
        // An overdue preferred date can still be waiting for watchOS. Replacing
        // it on each one-minute check would keep postponing it forever. Recover
        // a potentially lost request only after a bounded two-hour grace period.
        return existing < now.addingTimeInterval(-2 * 60 * 60) || existing > preferred
    }
}
