import Foundation

/// Prioritizes saved cigarette estimates over optional calibration work during a wake.
/// These are requested intervals and cooperative wall-time budgets, not guarantees
/// that watchOS will wake the app or allow an operation to run for that duration.
public enum TrackingRefreshPolicy {
    public static let preferredBackgroundInterval: TimeInterval = 15 * 60
    public static let recentLookback: TimeInterval = 15 * 60

    private static let backgroundWallTimeBudget: TimeInterval = 3
    private static let backgroundAnalysisBudget: TimeInterval = 2.25
    private static let maximumBackgroundCalibrationBudget: TimeInterval = 0.75
    private static let minimumBackgroundCalibrationBudget: TimeInterval = 0.25

    /// `analyze` must save its results before returning. Synchronization always
    /// follows analysis, including when cancellation or exhausted time prevents
    /// optional calibration. Foreground work retains the larger 20/6-second budgets.
    /// Callers must honor cancellation and their supplied budgets; this policy
    /// cannot preempt a synchronous sensor query or promise a background deadline.
    @MainActor
    public static func perform(
        isForeground: Bool,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        analyze: (TimeInterval) async -> Void,
        synchronize: () -> Void,
        calibrate: (TimeInterval) async -> Void
    ) async {
        let startedAt = isForeground ? nil : now()
        await analyze(isForeground ? 20 : backgroundAnalysisBudget)
        synchronize()

        guard Task.isCancelled == false else { return }
        if isForeground {
            await calibrate(6)
            return
        }

        let finishedAt = now()
        guard let startedAt, startedAt.isFinite, startedAt >= 0,
              finishedAt.isFinite, finishedAt >= startedAt else { return }
        let elapsed = finishedAt - startedAt
        guard elapsed.isFinite else { return }
        let remaining = backgroundWallTimeBudget - elapsed
        guard remaining >= minimumBackgroundCalibrationBudget else { return }
        await calibrate(min(maximumBackgroundCalibrationBudget, remaining))
    }
}
