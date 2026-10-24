import Foundation

/// Core Motion raises an Objective-C exception for a start older than three
/// days. Its retention is relative to the wall clock, not the delayed analysis
/// end or a saved replay cursor. Bound every native query immediately before use.
public enum SensorHistoryQuery {
    public static let retention: TimeInterval = 3 * 24 * 60 * 60
    public static let maximumDuration: TimeInterval = 12 * 60 * 60
    public static let boundaryMargin: TimeInterval = 5

    public static func range(from start: Date, to end: Date, now: Date = Date()) -> MotionHistoryRange? {
        guard [start, end, now].allSatisfy(MotionHistoryProcessor.isSupportedDate), start < end else { return nil }
        let upper = min(end, now)
        let lower = max(start, now.addingTimeInterval(-retention + boundaryMargin),
                        upper.addingTimeInterval(-maximumDuration))
        guard lower < upper else { return nil }
        return .init(start: lower, end: upper)
    }
}
