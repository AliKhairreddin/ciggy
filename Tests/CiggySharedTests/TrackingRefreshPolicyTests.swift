import XCTest
@testable import CiggyShared

@MainActor
final class TrackingRefreshPolicyTests: XCTestCase {
    func testForegroundSavesAndSynchronizesCountsBeforeCalibration() async {
        var actions: [String] = []
        var saved = false
        await TrackingRefreshPolicy.perform(
            isForeground: true,
            analyze: { budget in
                XCTAssertEqual(budget, 20)
                actions.append("analyze")
                saved = true
            },
            synchronize: {
                XCTAssertTrue(saved)
                actions.append("sync")
            },
            calibrate: { budget in
                XCTAssertEqual(budget, 6)
                actions.append("calibrate")
            }
        )
        XCTAssertEqual(actions, ["analyze", "sync", "calibrate"])
    }

    func testFastBackgroundAnalysisLeavesBoundedCalibrationTime() async {
        var clock: TimeInterval = 100
        var actions: [String] = []
        await TrackingRefreshPolicy.perform(
            isForeground: false, now: { clock },
            analyze: { budget in
                XCTAssertEqual(budget, 2.25)
                actions.append("analyze")
                clock += 0.2
            },
            synchronize: { actions.append("sync") },
            calibrate: { budget in
                XCTAssertEqual(budget, 0.75)
                XCTAssertLessThanOrEqual(clock - 100 + budget, 3)
                actions.append("calibrate")
            }
        )
        XCTAssertEqual(actions, ["analyze", "sync", "calibrate"])
    }

    func testActualAnalysisAndSyncElapsedTimeReduceCalibrationBudget() async {
        var clock: TimeInterval = 100
        var calibrationBudget: TimeInterval?
        await TrackingRefreshPolicy.perform(
            isForeground: false, now: { clock },
            analyze: { _ in clock += 2 },
            synchronize: { clock += 0.6 },
            calibrate: { calibrationBudget = $0 }
        )
        XCTAssertEqual(calibrationBudget ?? -1, 0.4, accuracy: 0.000_001)
    }

    func testExhaustedBudgetStillSynchronizesAndSkipsCalibration() async {
        for elapsed in [2.9, 3, 4, 20] {
            var clock: TimeInterval = 100
            var actions: [String] = []
            await TrackingRefreshPolicy.perform(
                isForeground: false, now: { clock },
                analyze: { _ in actions.append("analyze"); clock += elapsed },
                synchronize: { actions.append("sync") },
                calibrate: { _ in actions.append("calibrate") }
            )
            XCTAssertEqual(actions, ["analyze", "sync"], "Elapsed \(elapsed) must not start another sensor job")
        }
    }

    func testCancellationDuringAnalysisStillSynchronizesButSkipsCalibration() async {
        for isForeground in [false, true] {
            var actions: [String] = []
            let work = Task { @MainActor in
                await TrackingRefreshPolicy.perform(
                    isForeground: isForeground, now: { 100 },
                    analyze: { _ in
                        actions.append("analyze")
                        withUnsafeCurrentTask { $0?.cancel() }
                    },
                    synchronize: { actions.append("sync") },
                    calibrate: { _ in actions.append("calibrate") }
                )
            }
            await work.value
            XCTAssertEqual(actions, ["analyze", "sync"])
        }
    }

    func testCancellationDuringSynchronizationSkipsCalibration() async {
        var calibrated = false
        let work = Task { @MainActor in
            await TrackingRefreshPolicy.perform(
                isForeground: false, now: { 100 },
                analyze: { _ in },
                synchronize: { withUnsafeCurrentTask { $0?.cancel() } },
                calibrate: { _ in calibrated = true }
            )
        }
        await work.value
        XCTAssertFalse(calibrated)
    }

    func testInvalidOrBackwardsClockPreservesCountSyncAndSkipsOptionalWork() async {
        let readings: [(TimeInterval, TimeInterval)] = [
            (.nan, 100), (100, .nan), (.infinity, .infinity),
            (100, .infinity), (-.infinity, 100), (-1, 0), (100, 99)
        ]
        for (start, end) in readings {
            var clock = start
            var actions: [String] = []
            await TrackingRefreshPolicy.perform(
                isForeground: false, now: { clock },
                analyze: { budget in
                    XCTAssertTrue(budget.isFinite)
                    XCTAssertGreaterThan(budget, 0)
                    actions.append("analyze")
                    clock = end
                },
                synchronize: { actions.append("sync") },
                calibrate: { _ in actions.append("calibrate") }
            )
            XCTAssertEqual(actions, ["analyze", "sync"])
        }
    }
}
