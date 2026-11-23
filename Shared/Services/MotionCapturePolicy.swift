import Foundation

public enum MotionCapturePolicy {
    public static func shouldRenew(at now: Date, armedUntil: Date?) -> Bool {
        guard let armedUntil, MotionHistoryProcessor.isSupportedDate(armedUntil) else { return true }
        return armedUntil.timeIntervalSince(now) <= 6 * 60 * 60
    }
}

@MainActor
public final class WatchRefreshSchedule {
    public enum Wake {
        case foregroundEntered, foregroundEnded, backgroundGrant, check
    }

    private let defaults: UserDefaults
    private let scheduledKey = "BackgroundMotionMonitor.scheduledRefresh.v1"
    private var foregroundStart: Date?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func appointment(for wake: Wake, at now: Date, canSchedule: Bool) -> Date? {
        var scheduled = defaults.object(forKey: scheduledKey) as? Date
        switch wake {
        case .foregroundEntered:
            if foregroundStart == nil, MotionHistoryProcessor.isSupportedDate(now) { foregroundStart = now }
        case .foregroundEnded:
            if let start = foregroundStart, let due = scheduled, MotionHistoryProcessor.isSupportedDate(now),
               due >= start, due <= now {
                scheduled = nil
                defaults.removeObject(forKey: scheduledKey)
            }
            foregroundStart = nil
        case .backgroundGrant:
            scheduled = nil
            defaults.removeObject(forKey: scheduledKey)
        case .check:
            break
        }

        guard canSchedule, MotionHistoryProcessor.isSupportedDate(now) else { return nil }
        let preferred = now.addingTimeInterval(TrackingRefreshPolicy.preferredBackgroundInterval)
        if let due = scheduled, MotionHistoryProcessor.isSupportedDate(due),
           due <= preferred, now.timeIntervalSince(due) <= 2 * 60 * 60 {
            return nil
        }
        defaults.set(preferred, forKey: scheduledKey)
        return preferred
    }

    public func rejected(_ appointment: Date) {
        if defaults.object(forKey: scheduledKey) as? Date == appointment {
            defaults.removeObject(forKey: scheduledKey)
        }
    }
}
